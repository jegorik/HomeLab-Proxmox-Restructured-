#!/usr/bin/env bash
# =============================================================================
# Credentials Functions for LXC Base Template
# =============================================================================
# Secure credential management with HashiCorp Vault integration.
# Features:
#   - Userpass authentication to Vault
#   - Dynamic AWS credentials generation from Vault
#   - Transit engine verification
#   - Fallback to local files when Vault unavailable

# Prevent multiple sourcing
[[ -n "${_CREDENTIALS_SH_LOADED:-}" ]] && return 0
_CREDENTIALS_SH_LOADED=1

# AWS role for dynamic credentials
AWS_ROLE="${AWS_ROLE:-tofu_state_backup}"

# -----------------------------------------------------------------------------
# Read Configuration from terraform.tfvars
# -----------------------------------------------------------------------------

credentials_read_tfvars() {
    local var_name="$1"
    local default_value="${2:-}"
    
    if [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
        local value
        value=$(grep -E "^${var_name}\\s*=" "${TERRAFORM_DIR}/terraform.tfvars" 2>/dev/null | sed 's/.*=\s*"\([^"]*\)".*/\1/' | tr -d ' ')
        if [[ -n "${value}" ]]; then
            echo "${value}"
            return 0
        fi
    fi
    echo "${default_value}"
}

# -----------------------------------------------------------------------------
# Vault Configuration Check
# -----------------------------------------------------------------------------

credentials_check_configuration() {
    log_info "Configuring Vault connection..."

    # Check VAULT_ADDR: environment -> tfvars -> prompt
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        VAULT_ADDR=$(credentials_read_tfvars "vault_address")
    fi
    
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        log_warning "VAULT_ADDR not set"
        echo -n "Enter Vault address: "
        read -r VAULT_ADDR
        [[ -z "${VAULT_ADDR}" ]] && { log_error "VAULT_ADDR required"; return 1; }
    fi
    export VAULT_ADDR
    log_success "VAULT_ADDR=${VAULT_ADDR}"

    # Check VAULT_USERNAME: environment -> tfvars -> prompt
    if [[ -z "${VAULT_USERNAME:-}" ]]; then
        VAULT_USERNAME=$(credentials_read_tfvars "vault_username")
    fi
    
    if [[ -z "${VAULT_USERNAME:-}" ]]; then
        log_warning "VAULT_USERNAME not set"
        echo -n "Enter Vault username: "
        read -r VAULT_USERNAME
        [[ -z "${VAULT_USERNAME}" ]] && { log_error "VAULT_USERNAME required"; return 1; }
    fi
    export VAULT_USERNAME
    log_success "VAULT_USERNAME=${VAULT_USERNAME}"
    
    return 0
}

# -----------------------------------------------------------------------------
# Vault Connectivity Check
# -----------------------------------------------------------------------------

credentials_check_connectivity() {
    log_info "Checking Vault connectivity..."
    
    if ! command -v vault &>/dev/null; then
        log_error "Vault CLI not installed"
        return 1
    fi

    if ! vault status &>/dev/null; then
        log_error "Cannot connect to Vault at ${VAULT_ADDR}"
        return 1
    fi

    local sealed
    sealed=$(vault status -format=json 2>/dev/null | jq -r '.sealed')
    if [[ "${sealed}" == "true" ]]; then
        log_error "Vault is sealed. Run: vault operator unseal"
        return 1
    fi

    log_success "Connected to Vault (unsealed)"
    return 0
}

# -----------------------------------------------------------------------------
# Vault Authentication (userpass)
# -----------------------------------------------------------------------------

credentials_authenticate() {
    log_info "Checking Vault authentication..."
    
    # Check if already authenticated with valid token
    if vault token lookup &>/dev/null; then
        local display_name ttl
        display_name=$(vault token lookup -format=json | jq -r '.data.display_name')
        ttl=$(vault token lookup -format=json | jq -r '.data.ttl')
        log_success "Already authenticated as ${display_name} (TTL: ${ttl}s)"
        export VAULT_TOKEN=$(vault token lookup -format=json | jq -r '.data.id')
        
        # Get password for TF provider if not set
        if [[ -z "${TF_VAR_vault_password:-}" ]]; then
            echo -n "Enter Vault password for TF provider (${VAULT_USERNAME}): "
            read -s VAULT_PASSWORD
            echo ""
            export TF_VAR_vault_password="${VAULT_PASSWORD}"
        fi
        return 0
    fi

    # Perform userpass login
    log_info "Logging in as ${VAULT_USERNAME}..."
    echo -n "Enter Vault password: "
    read -s VAULT_PASSWORD
    echo ""

    if ! echo "${VAULT_PASSWORD}" | vault login -method=userpass username="${VAULT_USERNAME}" password=- -token-only &>/dev/null; then
        log_error "Authentication failed"
        return 1
    fi

    export VAULT_TOKEN=$(vault token lookup -format=json | jq -r '.data.id')
    export TF_VAR_vault_password="${VAULT_PASSWORD}"
    log_success "Authenticated successfully"
    return 0
}

# -----------------------------------------------------------------------------
# Verify Transit Engine
# -----------------------------------------------------------------------------

credentials_verify_transit() {
    log_info "Verifying Vault Transit engine..."
    
    local key path
    key=$(credentials_read_tfvars "transit_key_name" "tofu-state-encryption")
    path=$(credentials_read_tfvars "transit_engine_path" "transit")
    
    if vault read "${path}/keys/${key}" &>/dev/null; then
        log_success "Transit key '${key}' found"
    else
        log_info "Transit key '${key}' will be created by Terraform if needed"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Generate Dynamic AWS Credentials from Vault
# -----------------------------------------------------------------------------

credentials_generate_aws_credentials() {
    log_info "Generating AWS credentials from Vault (role: ${AWS_ROLE})..."
    
    # Check if S3 backend is configured
    if [[ ! -f "${TERRAFORM_DIR}/s3.backend.config" ]]; then
        log_info "S3 backend not configured - skipping AWS credentials"
        return 0
    fi

    # Clear any existing AWS profile settings to avoid conflicts
    unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_SESSION_TOKEN
    
    local creds
    creds=$(vault read -format=json aws/proxmox/creds/${AWS_ROLE} 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate AWS credentials from Vault"
        log_error "${creds}"
        return 1
    fi

    export AWS_ACCESS_KEY_ID=$(echo "${creds}" | jq -r '.data.access_key')
    export AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | jq -r '.data.secret_key')
    local lease_duration=$(echo "${creds}" | jq -r '.lease_duration')

    if [[ -z "${AWS_ACCESS_KEY_ID}" || "${AWS_ACCESS_KEY_ID}" == "null" ]]; then
        log_error "Failed to extract AWS credentials"
        return 1
    fi

    log_success "AWS credentials generated (TTL: $((lease_duration / 3600))h)"
    log_info "Waiting 10s for IAM propagation..."
    sleep 10
    log_success "AWS credentials ready"
    return 0
}

# -----------------------------------------------------------------------------
# Load Proxmox Credentials from Vault (with local fallback)
# -----------------------------------------------------------------------------

credentials_load_pve_from_vault() {
    log_info "Loading Proxmox credentials..."

    # Check if already set via environment
    if [[ -n "${TF_VAR_pve_root_password:-}" ]]; then
        log_success "Using TF_VAR_pve_root_password from environment"
        return 0
    fi

    # Build Vault path from tfvars
    local mount_path secret_name vault_path
    mount_path=$(credentials_read_tfvars "ephemeral_vault_mount_path" "secrets/proxmox/")
    secret_name=$(credentials_read_tfvars "proxmox_root_password_vault_path" "pve_root_password")
    vault_path="${mount_path}${secret_name}"

    # Try to fetch from Vault first (priority)
    if command -v vault &>/dev/null && [[ -n "${VAULT_TOKEN:-}" ]]; then
        local password
        password=$(vault kv get -field=password "${vault_path}" 2>/dev/null)
        
        if [[ -n "${password}" ]]; then
            export TF_VAR_pve_root_password="${password}"
            log_success "Loaded Proxmox password from Vault: ${vault_path}"
            return 0
        else
            log_warning "Could not fetch password from Vault path: ${vault_path}"
        fi
    fi

    # Fallback: local file
    local pve_password_file="${HOME}/.ssh/pve_root_password"
    if [[ -f "${pve_password_file}" ]]; then
        local perms
        perms=$(stat -c "%a" "${pve_password_file}" 2>/dev/null || stat -f "%p" "${pve_password_file}" 2>/dev/null | tail -c 4)
        
        if [[ "${perms}" != "600" ]]; then
            log_warning "Password file has insecure permissions: ${perms}"
            log_info "Fixing permissions..."
            chmod 600 "${pve_password_file}"
        fi

        export TF_VAR_pve_root_password
        TF_VAR_pve_root_password=$(cat "${pve_password_file}")
        log_success "Loaded password from local file: ${pve_password_file}"
        return 0
    fi

    # Final fallback: prompt
    log_warning "Falling back to manual password entry"
    echo -n "Enter Proxmox root@pam password: "
    read -rs TF_VAR_pve_root_password
    echo ""

    if [[ -z "${TF_VAR_pve_root_password}" ]]; then
        log_error "Password is required"
        return 1
    fi

    export TF_VAR_pve_root_password
    log_success "Password set from user input"
    return 0
}

# -----------------------------------------------------------------------------
# Load NetBox API Token from Vault
# -----------------------------------------------------------------------------

credentials_load_netbox_token() {
    log_info "Loading NetBox API token..."

    # Check if already set via environment
    if [[ -n "${TF_VAR_netbox_api_token:-}" ]]; then
        log_success "Using TF_VAR_netbox_api_token from environment"
        return 0
    fi

    # Build Vault path from tfvars
    local mount_path secret_name vault_path
    mount_path=$(credentials_read_tfvars "ephemeral_vault_mount_path" "secrets/proxmox/")
    secret_name=$(credentials_read_tfvars "netbox_api_token_vault_path" "netbox_api_token")
    vault_path="${mount_path}${secret_name}"

    # Try to fetch from Vault
    if command -v vault &>/dev/null && [[ -n "${VAULT_TOKEN:-}" ]]; then
        local token
        token=$(vault kv get -field=token "${vault_path}" 2>/dev/null)
        
        if [[ -n "${token}" ]]; then
            export TF_VAR_netbox_api_token="${token}"
            log_success "Loaded NetBox token from Vault: ${vault_path}"
            return 0
        else
            log_warning "Could not fetch token from Vault path: ${vault_path}"
        fi
    fi

    # Fallback: prompt
    log_warning "Falling back to manual token entry"
    echo -n "Enter NetBox API token: "
    read -rs TF_VAR_netbox_api_token
    echo ""

    if [[ -z "${TF_VAR_netbox_api_token}" ]]; then
        log_error "NetBox API token is required"
        return 1
    fi

    export TF_VAR_netbox_api_token
    log_success "NetBox token set from user input"
    return 0
}

# -----------------------------------------------------------------------------
# Load State Encryption Passphrase (OpenTofu)
# -----------------------------------------------------------------------------

credentials_load_passphrase() {
    log_info "Loading state encryption passphrase..."

    # Check if already set
    if [[ -n "${TF_VAR_passphrase:-}" ]]; then
        log_success "Using TF_VAR_passphrase from environment"
        return 0
    fi

    # Load from file
    local passphrase_file="${HOME}/.ssh/state_passphrase"
    if [[ -f "${passphrase_file}" ]]; then
        export TF_VAR_passphrase="${passphrase_file}"
        log_success "Using passphrase file: ${passphrase_file}"
        return 0
    fi

    log_info "State encryption passphrase not configured (optional)"
    return 0
}

# -----------------------------------------------------------------------------
# Master Initialization Function
# -----------------------------------------------------------------------------

credentials_initialize() {
    log_header "Loading Credentials"

    credentials_check_configuration || return 1
    credentials_check_connectivity || return 1
    credentials_authenticate || return 1
    credentials_verify_transit || return 1
    credentials_generate_aws_credentials || return 1
    credentials_load_pve_from_vault || return 1
    credentials_load_netbox_token || return 1
    credentials_load_passphrase || return 1

    log_success "All credentials loaded successfully"
    log_info "Environment: VAULT_TOKEN, VAULT_ADDR, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    return 0
}
