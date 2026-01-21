#!/usr/bin/env bash
# =============================================================================
# NetBox Settings Template - Deployment Script
# =============================================================================
# Modular deployment using vault.sh and terraform.sh scripts
#
# Usage:
#   ./deploy.sh              # Interactive menu
#   ./deploy.sh deploy       # Full deployment (Vault + Terraform)
#   ./deploy.sh destroy      # Destroy resources
#   ./deploy.sh plan         # Dry-run
#   ./deploy.sh status       # Check status
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
LOGS_DIR="${SCRIPT_DIR}/logs"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Log file
mkdir -p "${LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"

# Source modules
source "${SCRIPTS_DIR}/common.sh"
source "${SCRIPTS_DIR}/vault.sh"
source "${SCRIPTS_DIR}/terraform.sh"

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------

check_binaries() {
    log_header "Checking Required Binaries"
    local ok=true
    
    check_command "tofu" || check_command "terraform" || ok=false
    check_command "vault" "apt install vault" || ok=false
    check_command "jq" "apt install jq" || ok=false
    
    [[ "${ok}" == true ]] && log_success "All binaries found"
    return $([[ "${ok}" == true ]])
}

check_files() {
    log_header "Checking Configuration Files"
    local ok=true
    
    for f in main.tf variables.tf providers.tf backend.tf encryption.tf; do
        [[ -f "${TERRAFORM_DIR}/${f}" ]] && log_success "Found: ${f}" || { log_error "Missing: ${f}"; ok=false; }
    done
    
    [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]] && log_success "Found: terraform.tfvars" || log_warning "Missing: terraform.tfvars"
    [[ -f "${TERRAFORM_DIR}/s3.backend.config" ]] && log_success "Found: s3.backend.config" || log_warning "Missing: s3.backend.config"
    
    return $([[ "${ok}" == true ]])
}

# -----------------------------------------------------------------------------
# Main Workflows
# -----------------------------------------------------------------------------

deploy_full() {
    log_header "Full NetBox Settings Deployment"
    local start_time=$(date +%s)

    check_binaries || return 1
    check_files || return 1
    
    vault_initialize || return 1
    terraform_init || return 1
    terraform_validate || return 1
    terraform_apply || return 1
    
    local duration=$(( $(date +%s) - start_time ))
    log_header "Deployment Complete"
    log_success "Time: $((duration / 60))m $((duration % 60))s"
}

deploy_plan() {
    log_header "Dry-Run (Plan Only)"
    
    check_binaries || return 1
    check_files || return 1
    vault_initialize || return 1
    terraform_init || return 1
    terraform_validate || return 1
    terraform_plan || return 1
    
    log_success "Plan complete. Run './deploy.sh deploy' to apply."
}

deploy_destroy() {
    log_header "Destroy NetBox Configuration"
    
    check_binaries || return 1
    vault_initialize || return 1
    terraform_destroy || return 1
}

check_status() {
    log_header "Deployment Status"
    
    # Initialize Vault for state decryption
    vault_initialize || {
        log_warning "Vault auth failed - cannot check encrypted state"
        return 1
    }
    
    cd "${TERRAFORM_DIR}" || return 1
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    
    if ! ${iac_tool} state list &>/dev/null; then
        log_info "No Terraform state found - not deployed"
        return 0
    fi
    
    log_success "Infrastructure deployed"
    ${iac_tool} output 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Interactive Menu
# -----------------------------------------------------------------------------

show_menu() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║       NetBox Settings Template Deployment            ║"
    echo "║       OpenTofu/Terraform + Vault                     ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Deploy Configuration (full)"
    echo -e "  ${BLUE}2)${NC} Dry-Run / Plan"
    echo -e "  ${YELLOW}3)${NC} Check Status"
    echo -e "  ${RED}4)${NC} Destroy Configuration"
    echo ""
    echo -e "  ${BOLD}0)${NC} Exit"
    echo ""
}

interactive_menu() {
    while true; do
        show_menu
        echo -n "Select: "
        read -r choice
        echo ""
        
        case ${choice} in
            1) deploy_full; read -p "Press Enter..." ;;
            2) deploy_plan; read -p "Press Enter..." ;;
            3) check_status; read -p "Press Enter..." ;;
            4) deploy_destroy; read -p "Press Enter..." ;;
            0) exit 0 ;;
            *) log_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# CLI Help
# -----------------------------------------------------------------------------

show_help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  deploy    - Full deployment (Vault + Terraform)"
    echo "  destroy   - Destroy all NetBox configuration"
    echo "  plan      - Dry-run / plan only"
    echo "  status    - Check deployment status"
    echo "  help      - Show this help"
    echo ""
    echo "No arguments: Interactive menu"
    echo ""
    echo "Environment variables:"
    echo "  VAULT_ADDR     - Vault server address"
    echo "  VAULT_USERNAME - Vault username"
    echo "  AWS_ROLE       - AWS role for credentials (default: tofu_state_backup)"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    log_info "Started at $(date)"
    log_info "Log: ${LOG_FILE}"

    if [[ $# -eq 0 ]]; then
        interactive_menu
    else
        case "$1" in
            deploy)  deploy_full ;;
            destroy) deploy_destroy ;;
            plan)    deploy_plan ;;
            status)  check_status ;;
            help|--help|-h) show_help ;;
            *) log_error "Unknown: $1"; show_help; exit 1 ;;
        esac
    fi

    log_info "Completed at $(date)"
}

main "$@"
