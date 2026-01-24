#!/usr/bin/env bash
# =============================================================================
# Credentials Functions for Vault LXC Deployment
# =============================================================================
# This project is special - it deploys HashiCorp Vault itself, so it cannot
# use Vault for secrets. Uses local file-based credentials with security checks.
#
# WARNING: Keep credential files secure with proper permissions!

# Prevent multiple sourcing
[[ -n "${_CREDENTIALS_SH_LOADED:-}" ]] && return 0
_CREDENTIALS_SH_LOADED=1

# Default file paths
PVE_PASSWORD_FILE="${HOME}/.ssh/pve_root_password"
STATE_PASSPHRASE_FILE="${HOME}/.ssh/state_passphrase"
AWS_CREDENTIALS_FILE="${HOME}/.aws/credentials"

# -----------------------------------------------------------------------------
# Security Check for Credential Files
# -----------------------------------------------------------------------------

credentials_check_file_security() {
    local file="$1"
    local description="$2"
    
    if [[ ! -f "${file}" ]]; then
        return 1
    fi
    
    local perms
    perms=$(stat -c "%a" "${file}" 2>/dev/null || stat -f "%p" "${file}" 2>/dev/null | tail -c 4)
    
    if [[ "${perms}" != "600" ]]; then
        log_warning "${description} has insecure permissions: ${perms}"
        log_info "Fixing permissions to 600..."
        if chmod 600 "${file}"; then
            log_success "Permissions fixed for ${file}"
        else
            log_error "Failed to fix permissions for ${file}"
            return 1
        fi
    fi
    
    return 0
}

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
        credentials_check_file_security "${PVE_PASSWORD_FILE}" "PVE password file"
        
        export TF_VAR_pve_root_password
        TF_VAR_pve_root_password=$(cat "${PVE_PASSWORD_FILE}")
        log_success "Loaded password from: ${PVE_PASSWORD_FILE}"
        return 0
    fi

    # Prompt for password
    log_warning "PVE password file not found: ${PVE_PASSWORD_FILE}"
    log_info "You can create it with: echo 'your-password' > ${PVE_PASSWORD_FILE} && chmod 600 ${PVE_PASSWORD_FILE}"
    echo -n "Enter Proxmox root@pam password: "
    read -r -s TF_VAR_pve_root_password
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
        credentials_check_file_security "${STATE_PASSPHRASE_FILE}" "State passphrase file"
        export TF_VAR_passphrase="${STATE_PASSPHRASE_FILE}"
        log_success "Using passphrase file: ${STATE_PASSPHRASE_FILE}"
        return 0
    fi

    log_info "State encryption passphrase not configured (optional)"
    return 0
}

# -----------------------------------------------------------------------------
# Check/Load AWS Credentials for S3 Backend
# -----------------------------------------------------------------------------

credentials_check_aws() {
    log_info "Checking AWS credentials for S3 backend..."

    # Check if S3 backend is configured
    if [[ ! -f "${TERRAFORM_DIR}/s3.backend.config" ]]; then
        log_info "S3 backend not configured - skipping AWS check"
        return 0
    fi

    # Check for environment variables first (priority)
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_success "AWS credentials found in environment"
        return 0
    fi

    # Check AWS credentials file
    if [[ -f "${AWS_CREDENTIALS_FILE}" ]]; then
        credentials_check_file_security "${AWS_CREDENTIALS_FILE}" "AWS credentials file"
        log_success "AWS credentials file found: ${AWS_CREDENTIALS_FILE}"
        log_info "Using default AWS profile"
        return 0
    fi

    # Prompt for AWS credentials
    log_warning "AWS credentials not found"
    log_info "S3 backend requires AWS credentials"
    
    echo -n "Enter AWS Access Key ID (or press Enter to skip): "
    read -r aws_key
    
    if [[ -n "${aws_key}" ]]; then
        echo -n "Enter AWS Secret Access Key: "
        read -r -s aws_secret
        echo ""
        
        if [[ -n "${aws_secret}" ]]; then
            export AWS_ACCESS_KEY_ID="${aws_key}"
            export AWS_SECRET_ACCESS_KEY="${aws_secret}"
            log_success "AWS credentials set from user input"
            return 0
        fi
    fi

    log_warning "AWS credentials not configured - S3 backend may fail"
    log_info "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY or configure ~/.aws/credentials"
    return 0
}

# -----------------------------------------------------------------------------
# Display Security Recommendations
# -----------------------------------------------------------------------------

credentials_show_security_notice() {
    log_info "Security Recommendations:"
    echo "  - Store passwords in files with 600 permissions"
    echo "  - Use dedicated service accounts where possible"
    echo "  - After Vault is deployed, migrate secrets to Vault"
    echo "  - Regularly rotate credentials"
}

# -----------------------------------------------------------------------------
# Master Initialization Function
# -----------------------------------------------------------------------------

credentials_initialize() {
    log_header "Loading Credentials (File-based)"
    
    log_warning "This project uses file-based credentials (Vault not available)"
    credentials_show_security_notice
    echo ""

    credentials_load_pve_password || return 1
    credentials_load_passphrase || return 1
    credentials_check_aws || return 1

    log_success "Credentials loaded successfully"
    log_info "Environment: TF_VAR_pve_root_password (set)"
    return 0
}
