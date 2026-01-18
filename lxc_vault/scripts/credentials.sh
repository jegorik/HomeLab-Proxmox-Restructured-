#!/usr/bin/env bash
# =============================================================================
# Credentials Functions for Vault LXC Deployment
# =============================================================================
# Unlike lxc_netbox (which uses HashiCorp Vault), this project uses local
# file-based credentials since Vault is not yet deployed.

# Prevent multiple sourcing
[[ -n "${_CREDENTIALS_SH_LOADED:-}" ]] && return 0
_CREDENTIALS_SH_LOADED=1

# Default file paths
PVE_PASSWORD_FILE="${HOME}/.ssh/pve_root_password"
STATE_PASSPHRASE_FILE="${HOME}/.ssh/state_passphrase"

# -----------------------------------------------------------------------------
# Load Proxmox Credentials
# -----------------------------------------------------------------------------

credentials_load_pve_password() {
    log_info "Loading Proxmox credentials..."

    # Check if already set via environment variable
    if [[ -n "${TF_VAR_pve_root_password:-}" ]]; then
        log_success "Using TF_VAR_pve_root_password from environment"
        return 0
    fi

    # Try to load from file
    if [[ -f "${PVE_PASSWORD_FILE}" ]]; then
        local perms
        perms=$(stat -c "%a" "${PVE_PASSWORD_FILE}" 2>/dev/null || stat -f "%p" "${PVE_PASSWORD_FILE}" 2>/dev/null | tail -c 4)
        
        if [[ "${perms}" != "600" ]]; then
            log_warning "Password file has insecure permissions: ${perms}"
            log_info "Fixing permissions..."
            chmod 600 "${PVE_PASSWORD_FILE}"
        fi

        export TF_VAR_pve_root_password
        TF_VAR_pve_root_password=$(cat "${PVE_PASSWORD_FILE}")
        log_success "Loaded password from: ${PVE_PASSWORD_FILE}"
        return 0
    fi

    # Prompt for password
    log_warning "PVE password not found"
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
    if [[ -f "${STATE_PASSPHRASE_FILE}" ]]; then
        export TF_VAR_passphrase="${STATE_PASSPHRASE_FILE}"
        log_success "Using passphrase file: ${STATE_PASSPHRASE_FILE}"
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

    credentials_load_pve_password || return 1
    credentials_load_passphrase || return 1
    credentials_check_aws || return 1

    log_success "Credentials loaded successfully"
    log_info "Environment: TF_VAR_pve_root_password (set)"
    return 0
}
