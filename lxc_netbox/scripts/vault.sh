#!/usr/bin/env bash
# =============================================================================
# Vault Functions for NetBox Deployment
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_VAULT_SH_LOADED:-}" ]] && return 0
_VAULT_SH_LOADED=1

# AWS role for dynamic credentials
AWS_ROLE="${AWS_ROLE:-tofu_state_backup}"

# Check and prompt for Vault configuration
vault_check_configuration() {
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        log_warning "VAULT_ADDR not set"
        echo -n "Enter Vault address: "
        read -r VAULT_ADDR
        [[ -z "${VAULT_ADDR}" ]] && { log_error "VAULT_ADDR required"; return 1; }
    fi
    export VAULT_ADDR
    log_success "VAULT_ADDR=${VAULT_ADDR}"

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

# Check Vault connectivity
vault_check_connectivity() {
    log_info "Checking Vault connectivity..."
    
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

# Authenticate with Vault
vault_authenticate() {
    log_info "Checking Vault authentication..."
    
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

    log_info "Logging in as ${VAULT_USERNAME}..."
    echo -n "Enter Vault password: "
    read -s VAULT_PASSWORD
    echo ""

    if ! vault login -method=userpass username="${VAULT_USERNAME}" password="${VAULT_PASSWORD}" -token-only &>/dev/null; then
        log_error "Authentication failed"
        return 1
    fi

    export VAULT_TOKEN=$(vault token lookup -format=json | jq -r '.data.id')
    export TF_VAR_vault_password="${VAULT_PASSWORD}"
    log_success "Authenticated successfully"
    return 0
}

# Generate dynamic AWS credentials
vault_generate_aws_credentials() {
    log_info "Generating AWS credentials from Vault..."
    
    unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_SESSION_TOKEN
    
    local creds
    creds=$(vault read -format=json aws/proxmox/creds/${AWS_ROLE} 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate AWS credentials"
        log_error "${creds}"
        return 1
    fi

    export AWS_ACCESS_KEY_ID=$(echo "${creds}" | jq -r '.data.access_key')
    export AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | jq -r '.data.secret_key')
    export LEASE_DURATION=$(echo "${creds}" | jq -r '.lease_duration')
    export LEASE_ID=$(echo "${creds}" | jq -r '.lease_id')

    if [[ -z "${AWS_ACCESS_KEY_ID}" || "${AWS_ACCESS_KEY_ID}" == "null" ]]; then
        log_error "Failed to extract AWS credentials"
        return 1
    fi

    log_success "AWS credentials generated (TTL: $((LEASE_DURATION / 3600))h)"
    log_info "Waiting 10s for IAM propagation..."
    sleep 10
    log_success "AWS credentials ready"
    return 0
}

# Verify Transit engine
vault_verify_transit() {
    log_info "Verifying Vault Transit engine..."
    local key="${transit_key_name:-tofu-state-encryption}"
    local path="${transit_engine_path:-transit}"
    
    if vault read "${path}/keys/${key}" &>/dev/null; then
        log_success "Transit key '${key}' found"
    else
        log_info "Transit key will be created by Terraform"
    fi
    return 0
}

# Master initialization function
vault_initialize() {
    log_header "Vault Authentication"

    vault_check_configuration || return 1
    vault_check_connectivity || return 1
    vault_authenticate || return 1
    vault_verify_transit || return 1
    vault_generate_aws_credentials || return 1

    log_success "Vault initialization complete"
    log_info "Environment: VAULT_TOKEN, VAULT_ADDR, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    return 0
}
