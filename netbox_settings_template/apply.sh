#!/usr/bin/env bash
# =============================================================================
# NetBox Settings Template - Wrapper Script
# =============================================================================
# Simplifies running Terraform with Vault authentication

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Source modules
source "${SCRIPTS_DIR}/common.sh"

# -----------------------------------------------------------------------------
# Main Functions
# -----------------------------------------------------------------------------

check_vault_token() {
    log_header "Checking Vault Authentication"
    
    if [[ -n "${VAULT_TOKEN:-}" ]]; then
        log_success "VAULT_TOKEN is set"
        return 0
    fi
    
    # Try to load from file
    local token_file="${HOME}/.vault-token"
    if [[ -f "${token_file}" ]]; then
        export VAULT_TOKEN
        VAULT_TOKEN=$(cat "${token_file}")
        log_success "Loaded token from: ${token_file}"
        return 0
    fi
    
    log_warning "VAULT_TOKEN not found automatically"
    log_info ""
    log_info "You can either:"
    log_info "  1. Enter token manually now"
    log_info "  2. Set it via: export VAULT_TOKEN=\$(vault print token)"
    log_info ""
    
    # Prompt for manual input
    read -rp "Enter VAULT_TOKEN (or press Enter to cancel): " manual_token
    
    if [[ -n "${manual_token}" ]]; then
        export VAULT_TOKEN="${manual_token}"
        log_success "VAULT_TOKEN set manually"
        return 0
    fi
    
    log_error "VAULT_TOKEN not provided"
    return 1
}

run_terraform() {
    local cmd="$1"
    shift  # Remove first arg, keep the rest
    cd "${TERRAFORM_DIR}"
    
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    
    log_info "Running: ${iac_tool} ${cmd} $*"
    ${iac_tool} "${cmd}" "$@"
}

show_help() {
    echo "Usage: $0 [init|plan|apply|destroy]"
    echo ""
    echo "Commands:"
    echo "  init    - Initialize Terraform"
    echo "  plan    - Preview changes"
    echo "  apply   - Apply changes"
    echo "  destroy - Destroy resources"
    echo ""
    echo "Prerequisites:"
    echo "  export VAULT_ADDR='https://vault.example.com:8200'"
    echo "  export VAULT_TOKEN=\$(vault print token)"
    echo ""
}

# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
    show_help
    exit 1
fi

case "$1" in
    init)
        run_terraform "init"
        ;;
    plan)
        check_vault_token || exit 1
        run_terraform "plan"
        ;;
    apply)
        check_vault_token || exit 1
        run_terraform "apply" "-auto-approve"
        ;;
    destroy)
        check_vault_token || exit 1
        run_terraform "destroy"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
