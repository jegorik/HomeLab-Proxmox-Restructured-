#!/usr/bin/env bash
# =============================================================================
# VM OpenSUSE Tumbleweed - Deployment Script
# =============================================================================
# Simplified deployment using modular scripts
#
# Usage:
#   ./deploy.sh              # Interactive menu
#   ./deploy.sh deploy       # Full deployment
#   ./deploy.sh destroy      # Destroy infrastructure
#   ./deploy.sh plan         # Dry-run
#   ./deploy.sh ansible      # Run Ansible only (requires VAULT_TOKEN)
#   ./deploy.sh terraform    # Terraform only (no Ansible)
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
# shellcheck source=scripts/vault.sh
source "${SCRIPTS_DIR}/vault.sh"
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
    check_command "vault" "apt install vault" || ok=false
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
        log_warning "Missing: terraform.tfvars (copy from terraform.tfvars.example)"
    fi
    
    [[ "${ok}" == true ]]
}

# -----------------------------------------------------------------------------
# Main Workflows
# -----------------------------------------------------------------------------

deploy_full() {
    log_header "Full VM Infrastructure Deployment"
    local start_time
    start_time=$(date +%s)

    check_binaries || return 1
    check_files || return 1
    
    vault_initialize || return 1
    terraform_init || return 1
    terraform_validate || return 1
    terraform_apply || return 1
    
    ansible_create_inventory || return 1
    
    # Get IP to wait for boot
    local vm_ip
    vm_ip=$(terraform_get_output "vm_ip_address" 2>/dev/null)
    
    if [[ -z "${vm_ip}" ]]; then
        log_error "Could not get VM IP from Terraform"
        return 1
    fi

    log_info "Waiting for VM to fully boot and SSH to break in..."
    wait_for_port "${vm_ip}" 22 300 || return 1

    # Extra wait for cloud-init to complete
    log_info "Waiting 30s for cloud-init to complete..."
    sleep 30

    # Retry connectivity test
    local retry=0
    while [[ ${retry} -lt 3 ]]; do
        ansible_test && break
        retry=$((retry + 1))
        [[ ${retry} -lt 3 ]] && { log_warning "Retry ${retry}/3..."; sleep 10; }
    done
    [[ ${retry} -eq 3 ]] && { log_error "Connectivity failed after 3 retries"; return 1; }
    
    ansible_deploy || return 1
    
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
    log_header "Destroy Infrastructure"
    
    check_binaries || return 1
    vault_initialize || return 1
    terraform_destroy || return 1
    
    # Cleanup
    rm -f "${ANSIBLE_DIR}/inventory.yml"
    rm -f "${TERRAFORM_DIR}/tfplan"
    
    log_success "Infrastructure destroyed"
    log_info "Note: Persistent data disk (if unmanaged by Terraform) might remain, but here modules manage it."
}

deploy_terraform_only() {
    log_header "Terraform Only (No Ansible)"
    
    check_binaries || return 1
    check_files || return 1
    vault_initialize || return 1
    terraform_init || return 1
    terraform_validate || return 1
    terraform_apply || return 1
    
    log_success "Terraform apply complete"
    log_info "Run './deploy.sh ansible' to configure the VM"
}

deploy_ansible_only() {
    log_header "Ansible Only"
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "VAULT_TOKEN not set, initializing Vault..."
        vault_initialize || return 1
    fi
    
    check_binaries || return 1
    ansible_create_inventory || return 1
    ansible_test || return 1
    ansible_deploy || return 1
}

deploy_status() {
    log_header "Infrastructure Status"
    
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    cd "${TERRAFORM_DIR}" || return 1

    if [[ -f "terraform.tfstate" ]] || [[ -f ".terraform/terraform.tfstate" ]]; then
        log_info "Terraform outputs:"
        ${iac_tool} output 2>/dev/null || log_warning "No outputs available"
    else
        log_warning "No local state found (may be using remote state)"
    fi

    # Check if VM is reachable
    local vm_ip
    vm_ip=$(${iac_tool} output -raw vm_ip_address 2>/dev/null || echo "")
    
    if [[ -n "${vm_ip}" ]]; then
        log_info "Checking VM connectivity..."
        if nc -z -w 2 "${vm_ip}" 22 2>/dev/null; then
            log_success "VM is reachable at ${vm_ip}:22"
        else
            log_warning "VM is not reachable at ${vm_ip}:22"
        fi
    fi
}

show_menu() {
    echo ""
    echo -e "${BOLD}${CYAN}VM OpenSUSE Tumbleweed - Deployment Menu${NC}"
    echo "======================================"
    echo "1) Deploy    - Full deployment (Terraform + Ansible)"
    echo "2) Plan      - Dry-run, show changes"
    echo "3) Terraform - Terraform only (create VM)"
    echo "4) Ansible   - Ansible only (configure VM)"
    echo "5) Status    - Show infrastructure status"
    echo "6) Destroy   - Destroy infrastructure"
    echo "7) Exit"
    echo ""
    echo -n "Select option [1-7]: "
    read -r choice
    
    case "${choice}" in
        1) deploy_full ;;
        2) deploy_plan ;;
        3) deploy_terraform_only ;;
        4) deploy_ansible_only ;;
        5) deploy_status ;;
        6) deploy_destroy ;;
        7) exit 0 ;;
        *) log_error "Invalid option"; show_menu ;;
    esac
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

main() {
    log_info "Starting VM OpenSUSE Tumbleweed deployment"
    log_info "Log file: ${LOG_FILE}"
    
    case "${1:-}" in
        deploy)    deploy_full ;;
        plan)      deploy_plan ;;
        terraform) deploy_terraform_only ;;
        ansible)   deploy_ansible_only ;;
        status)    deploy_status ;;
        destroy)   deploy_destroy ;;
        "")        show_menu ;;
        *)
            echo "Usage: $0 {deploy|plan|terraform|ansible|status|destroy}"
            exit 1
            ;;
    esac
}

main "$@"
