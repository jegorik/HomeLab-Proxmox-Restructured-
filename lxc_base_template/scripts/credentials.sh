#!/usr/bin/env bash
# =============================================================================
# Credentials Functions for LXC Base Template
# =============================================================================
# Retrieves secrets from HashiCorp Vault for deployment
# Vault address is prompted (no hardcoded IPs for flexibility)

# Prevent multiple sourcing
[[ -n "${_CREDENTIALS_SH_LOADED:-}" ]] && return 0
_CREDENTIALS_SH_LOADED=1

# -----------------------------------------------------------------------------
# Vault Configuration
# -----------------------------------------------------------------------------

credentials_configure_vault() {
    log_info "Configuring Vault connection..."

    # Check if VAULT_ADDR is set
    if [[ -n "${VAULT_ADDR:-}" ]]; then
        log_success "Using VAULT_ADDR from environment: ${VAULT_ADDR}"
    else
        # Prompt for Vault address
        echo -e -n "${YELLOW}Enter Vault address (e.g., https://vault.example.com:8200): ${NC}"
        read -r VAULT_ADDR
        
        if [[ -z "${VAULT_ADDR}" ]]; then
            log_error "Vault address is required"
            return 1
        fi
        export VAULT_ADDR
        log_success "Vault address set: ${VAULT_ADDR}"
    fi

    # Check if VAULT_TOKEN is set
    if [[ -n "${VAULT_TOKEN:-}" ]]; then
        log_success "Using VAULT_TOKEN from environment"
    else
        # Try to load from file
        local token_file="${HOME}/.vault-token"
        if [[ -f "${token_file}" ]]; then
            export VAULT_TOKEN
            VAULT_TOKEN=$(cat "${token_file}")
            log_success "Loaded token from: ${token_file}"
        else
            # Prompt for token
            echo -e -n "${YELLOW}Enter Vault token: ${NC}"
            read -rs VAULT_TOKEN
            echo ""
            
            if [[ -z "${VAULT_TOKEN}" ]]; then
                log_error "Vault token is required"
                return 1
            fi
            export VAULT_TOKEN
            log_success "Vault token set from user input"
        fi
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Verify Vault Connection
# -----------------------------------------------------------------------------

credentials_verify_vault() {
    log_info "Verifying Vault connection..."
    
    if ! command -v vault &>/dev/null; then
        log_warning "Vault CLI not installed - skipping verification"
        log_info "Terraform will verify connection during apply"
        return 0
    fi

    if vault status &>/dev/null; then
        log_success "Vault is reachable and unsealed"
        return 0
    else
        log_error "Cannot connect to Vault at ${VAULT_ADDR}"
        log_info "Check that Vault is running and unsealed"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Load Proxmox Credentials from Vault
# -----------------------------------------------------------------------------

credentials_load_pve_from_vault() {
    log_info "Loading Proxmox credentials from Vault..."

    local vault_path="${VAULT_PVE_SECRET_PATH:-secret/data/proxmox/root}"

    # Check if already set via environment
    if [[ -n "${TF_VAR_pve_root_password:-}" ]]; then
        log_success "Using TF_VAR_pve_root_password from environment"
        return 0
    fi

    # Try to fetch from Vault using CLI
    if command -v vault &>/dev/null; then
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

    # Fallback: prompt for password
    log_warning "Falling back to manual password entry"
    echo -e -n "${YELLOW}Enter Proxmox root@pam password: ${NC}"
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
    log_info "Loading NetBox API token from Vault..."

    local vault_path="${VAULT_NETBOX_SECRET_PATH:-secret/data/netbox/api}"

    # Check if already set via environment
    if [[ -n "${TF_VAR_netbox_api_token:-}" ]]; then
        log_success "Using TF_VAR_netbox_api_token from environment"
        return 0
    fi

    # Try to fetch from Vault using CLI
    if command -v vault &>/dev/null; then
        local token
        token=$(vault kv get -field=api_token "${vault_path}" 2>/dev/null)
        
        if [[ -n "${token}" ]]; then
            export TF_VAR_netbox_api_token="${token}"
            log_success "Loaded NetBox token from Vault: ${vault_path}"
            return 0
        else
            log_warning "Could not fetch token from Vault path: ${vault_path}"
        fi
    fi

    # Fallback: prompt for token
    log_warning "Falling back to manual token entry"
    echo -e -n "${YELLOW}Enter NetBox API token: ${NC}"
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
# Check AWS Credentials for S3 Backend
# -----------------------------------------------------------------------------

credentials_check_aws() {
    log_info "Checking AWS credentials for S3 backend..."

    # Check if S3 backend is configured
    if [[ ! -f "${TERRAFORM_DIR}/s3.backend.config" ]]; then
        log_info "S3 backend not configured - skipping AWS check"
        return 0
    fi

    # Check for environment variables
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_success "AWS credentials found in environment"
        return 0
    fi

    # Check AWS CLI default profile
    if command -v aws &>/dev/null; then
        if aws sts get-caller-identity &>/dev/null; then
            log_success "AWS credentials configured via CLI"
            return 0
        fi
    fi

    log_warning "AWS credentials not found - S3 backend may fail"
    log_info "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
    return 0
}

# -----------------------------------------------------------------------------
# Master Initialization Function
# -----------------------------------------------------------------------------

credentials_initialize() {
    log_header "Loading Credentials"

    credentials_configure_vault || return 1
    credentials_verify_vault || return 1
    credentials_load_pve_from_vault || return 1
    credentials_load_netbox_token || return 1
    credentials_load_passphrase || return 1
    credentials_check_aws || return 1

    log_success "All credentials loaded successfully"
    return 0
}
