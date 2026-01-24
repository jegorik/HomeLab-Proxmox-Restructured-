#!/usr/bin/env bash
# =============================================================================
# HashiCorp Vault LXC Container - Deployment Script
# =============================================================================
# Simplified deployment using modular scripts
#
# Usage:
#   ./deploy.sh              # Interactive menu
#   ./deploy.sh deploy       # Full deployment
#   ./deploy.sh destroy      # Destroy infrastructure
#   ./deploy.sh plan         # Dry-run
#   ./deploy.sh ansible      # Run Ansible only
#   ./deploy.sh status       # Check status
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
LOGS_DIR="${SCRIPT_DIR}/logs"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Log file
mkdir -p "${LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"

# Source modules
# shellcheck source=scripts/common.sh
source "${SCRIPTS_DIR}/common.sh"
source "${SCRIPTS_DIR}/credentials.sh"
# shellcheck source=scripts/terraform.sh
source "${SCRIPTS_DIR}/terraform.sh"
# shellcheck source=scripts/ansible.sh
source "${SCRIPTS_DIR}/ansible.sh"

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------

check_binaries() {
    log_header "Checking Required Binaries"
    local ok=true
    
    check_command "tofu" || check_command "terraform" || ok=false
    check_command "ansible" "pip install ansible" || ok=false
    check_command "ansible-playbook" || ok=false
    check_command "jq" "apt install jq" || ok=false
    check_command "ssh" || ok=false
    
    [[ "${ok}" == true ]] && log_success "All binaries found"
    [[ "${ok}" == true ]]
}

check_files() {
    log_header "Checking Configuration Files"
    local ok=true
    
    for f in main.tf variables.tf providers.tf backend.tf; do
        if [[ -f "${TERRAFORM_DIR}/${f}" ]]; then
            log_success "Found: ${f}"
        else
            log_error "Missing: ${f}"
            ok=false
        fi
    done
    
    if [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
        log_success "Found: terraform.tfvars"
    else
        log_warning "Missing: terraform.tfvars"
    fi
    
    [[ "${ok}" == true ]]
}

# -----------------------------------------------------------------------------
# Main Workflows
# -----------------------------------------------------------------------------

deploy_full() {
    log_header "Full Infrastructure Deployment"
    local start_time
    start_time=$(date +%s)

    check_binaries || return 1
    check_files || return 1
    
    credentials_initialize || return 1
    terraform_init || return 1
    terraform_validate || return 1
    terraform_apply || return 1
    
    ansible_create_inventory || return 1
    
    log_info "Waiting for container connectivity..."

    # Retry connectivity test with polling
    local retry=0
    local max_retries=30
    local connected=false

    # Switch to Ansible directory for config
    cd "${ANSIBLE_DIR}" || return 1

    while [[ ${retry} -lt ${max_retries} ]]; do
        if ansible vault -m ping -i inventory.yml &>/dev/null; then
            connected=true
            log_success "Connectivity OK"
            break
        fi

        retry=$((retry + 1))
        # Log every 5 seconds (assuming ~2s per loop iteration including sleep)
        if (( retry % 5 == 0 )); then
            log_info "Waiting for container... (${retry}/${max_retries})"
        fi
        sleep 2
    done

    if [[ "${connected}" == false ]]; then
        log_error "Connectivity failed after ${max_retries} attempts"
        return 1
    fi
    
    ansible_deploy || return 1
    
    local duration=$(( $(date +%s) - start_time ))
    log_header "Deployment Complete"
    log_success "Time: $((duration / 60))m $((duration % 60))s"
    
    echo ""
    log_info "Next steps:"
    echo "  1. Access Vault UI: https://<container-ip>:8200"
    echo "  2. Get root token: ssh ansible@<ip> sudo cat /root/vault-keys.txt"
    echo ""
}

deploy_plan() {
    log_header "Dry-Run (Plan Only)"
    
    check_binaries || return 1
    check_files || return 1
    credentials_initialize || return 1
    terraform_init || return 1
    terraform_validate || return 1
    terraform_plan || return 1
    
    log_success "Plan complete. Run './deploy.sh deploy' to apply."
}

deploy_destroy() {
    log_header "Destroy Infrastructure"
    
    check_binaries || return 1
    credentials_initialize || return 1
    terraform_destroy || return 1
    
    # Cleanup
    [[ -f "${ANSIBLE_DIR}/inventory.yml" ]] && rm "${ANSIBLE_DIR}/inventory.yml" && log_info "Removed inventory.yml"
}

deploy_ansible_only() {
    log_header "Ansible Only"
    
    if [[ ! -f "${ANSIBLE_DIR}/inventory.yml" ]]; then
        log_warning "inventory.yml not found"
        log_info "Creating inventory from Terraform outputs..."
        ansible_create_inventory || return 1
    fi
    
    ansible_test || return 1
    ansible_deploy || return 1
}

deploy_terraform_only() {
    log_header "Terraform Only (No Ansible)"
    local start_time
    start_time=$(date +%s)

    check_binaries || return 1
    check_files || return 1
    
    credentials_initialize || return 1
    terraform_init || return 1
    terraform_validate || return 1
    terraform_apply || return 1
    
    local duration=$(( $(date +%s) - start_time ))
    log_header "Terraform Deployment Complete"
    log_success "Time: $((duration / 60))m $((duration % 60))s"
    
    echo ""
    log_info "Infrastructure deployed. To configure with Ansible:"
    echo "  ./deploy.sh ansible"
    echo ""
}

check_status() {
    log_header "Deployment Status"
    
    # Initialize credentials for state decryption
    credentials_initialize || {
        log_warning "Credentials init failed - cannot check encrypted state"
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
    
    if [[ -f "${ANSIBLE_DIR}/inventory.yml" ]]; then
        log_success "Ansible inventory exists"
        cd "${ANSIBLE_DIR}"
        if ansible vault -m ping -i inventory.yml &>/dev/null; then
            log_success "Container reachable"
        else
            log_warning "Container not reachable"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Interactive Menu
# -----------------------------------------------------------------------------

show_menu() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║       HashiCorp Vault LXC Container Deployment       ║"
    echo "║       OpenTofu/Terraform + Ansible                   ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Deploy Infrastructure (full)"
    echo -e "  ${BLUE}2)${NC} Dry-Run / Plan"
    echo -e "  ${YELLOW}3)${NC} Check Status"
    echo -e "  ${RED}4)${NC} Destroy Infrastructure"
    echo ""
    echo -e "  ${CYAN}5)${NC} Ansible Only"
    echo -e "  ${BLUE}6)${NC} Terraform Only (no Ansible)"
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
            1) deploy_full; read -r -p "Press Enter..." ;;
            2) deploy_plan; read -r -p "Press Enter..." ;;
            3) check_status; read -r -p "Press Enter..." ;;
            4) deploy_destroy; read -r -p "Press Enter..." ;;
            5) deploy_ansible_only; read -r -p "Press Enter..." ;;
            6) deploy_terraform_only; read -r -p "Press Enter..." ;;
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
    echo "  deploy    - Full deployment (Terraform + Ansible)"
    echo "  destroy   - Destroy all infrastructure"
    echo "  plan      - Dry-run / plan only"
    echo "  status    - Check deployment status"
    echo "  ansible   - Run Ansible only"
    echo "  terraform - Terraform only (no Ansible)"
    echo "  help      - Show this help"
    echo ""
    echo "No arguments: Interactive menu"
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
            ansible) deploy_ansible_only ;;
            terraform) deploy_terraform_only ;;
            help|--help|-h) show_help ;;
            *) log_error "Unknown: $1"; show_help; exit 1 ;;
        esac
    fi

    log_info "Completed at $(date)"
}

main "$@"
