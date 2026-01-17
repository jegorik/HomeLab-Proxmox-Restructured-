#!/usr/bin/env bash
# =============================================================================
# NetBox Settings Template - Wrapper Script
# =============================================================================
# Simplifies running Terraform with credential handling

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Source modules
source "${SCRIPTS_DIR}/common.sh"
source "${SCRIPTS_DIR}/credentials.sh"

# -----------------------------------------------------------------------------
# Main Functions
# -----------------------------------------------------------------------------

configure_credentials() {
    log_header "Loading Credentials"
    
    # Configure Vault and fetch NetBox credentials
    credentials_configure_vault || return 1
    credentials_verify_vault || return 1
    credentials_load_netbox_token || return 1
    
    log_success "NetBox credentials loaded"
}

run_terraform() {
    local cmd="$1"
    cd "${TERRAFORM_DIR}"
    
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    
    log_info "Running: ${iac_tool} ${cmd}"
    ${iac_tool} "${cmd}"
}

# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [init|plan|apply|destroy]"
    exit 1
fi

configure_credentials || exit 1

case "$1" in
    init)    run_terraform "init" ;;
    plan)    run_terraform "plan" ;;
    apply)   run_terraform "apply" ;;
    destroy) run_terraform "destroy" ;;
    *)       echo "Unknown command: $1"; exit 1 ;;
esac
