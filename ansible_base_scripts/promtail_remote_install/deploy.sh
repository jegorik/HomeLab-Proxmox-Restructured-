#!/usr/bin/env bash
# =============================================================================
# Promtail Remote Install - Deployment Script
# =============================================================================
# Retrieves Loki credentials from HashiCorp Vault and runs the Ansible
# playbook to install/update Promtail on all inventory hosts.
#
# Usage:
#   ./deploy.sh              # Interactive menu
#   ./deploy.sh run          # Run playbook (Vault auth + ansible-playbook)
#   ./deploy.sh check        # Ansible dry-run (--check)
#   ./deploy.sh status       # Ping all hosts
#   ./deploy.sh help         # Show this help
#
# Environment variables (override config file / prompts):
#   VAULT_ADDR                  - Vault server URL
#   VAULT_USERNAME              - Vault userpass username
#   VAULT_TOKEN                 - Existing Vault token (skips login)
#   PROMTAIL_VAULT_SECRET_PATH  - Vault path to the secret (e.g. secrets/proxmox/promtail)
#   PROMTAIL_LOKI_URL           - Loki push URL (if not stored in Vault secret)
#
# Config file (optional, deploy.conf next to this script):
#   vault_addr=https://vault.example.com:8200
#   vault_username=operator
#   vault_secret_path=secrets/proxmox/promtail
#   loki_url=https://loki.example.com
#   loki_username=promtail
#
# Minimum required secret in Vault (only password is mandatory):
#   vault kv put secrets/proxmox/promtail password="<loki-password>"
#
# Optional — store url and username in the secret too:
#   vault kv put secrets/proxmox/promtail \
#     url="https://loki.example.com" \
#     username="promtail" \
#     password="<loki-password>"
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail

# Resolve directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Log file
mkdir -p "${LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# Source modules
# shellcheck source=scripts/common.sh
source "${SCRIPTS_DIR}/common.sh"
# shellcheck source=scripts/vault.sh
source "${SCRIPTS_DIR}/vault.sh"

# =============================================================================
# Pre-flight
# =============================================================================

check_binaries() {
    log_header "Checking Required Binaries"
    local ok=true

    check_command "ansible-playbook" "pip install ansible" || ok=false
    check_command "ansible"          "pip install ansible" || ok=false
    check_command "vault"            "https://developer.hashicorp.com/vault/install" || ok=false
    check_command "jq"               "apt/brew install jq" || ok=false

    [[ "${ok}" == true ]] && log_success "All binaries available"
    [[ "${ok}" == true ]]
}

check_files() {
    log_header "Checking Required Files"
    local ok=true

    if [[ -f "${ANSIBLE_DIR}/inventory.yml" ]]; then
        log_success "inventory.yml found"
    else
        log_error "inventory.yml not found"
        log_info "Copy and edit the example:"
        log_info "  cp ${ANSIBLE_DIR}/inventory.yml.example ${ANSIBLE_DIR}/inventory.yml"
        ok=false
    fi

    if [[ -f "${ANSIBLE_DIR}/playbook.yml" ]]; then
        log_success "playbook.yml found"
    else
        log_error "playbook.yml not found"
        ok=false
    fi

    [[ "${ok}" == true ]]
}

# =============================================================================
# Ansible helpers
# =============================================================================

# Ping all hosts in inventory
ansible_ping() {
    log_header "Testing Host Connectivity"
    cd "${ANSIBLE_DIR}" || return 1
    ansible all -m ping -i inventory.yml | tee -a "${LOG_FILE}"
}

# Write Loki credentials to a temp vars file.
# Sets global PROMTAIL_VARS_FILE — must NOT be called in a subshell,
# because the trap EXIT would delete the file before the caller reads it.
_create_vars_file() {
    local loki_url="${PROMTAIL_LOKI_URL:-}"
    local loki_user="${PROMTAIL_LOKI_USER:-promtail}"
    local loki_pass="${PROMTAIL_LOKI_PASSWORD:-}"

    if [[ -z "${loki_url}" ]]; then
        log_error "Loki URL is not set."
        log_info "Set it in one of these ways (in priority order):"
        log_info "  1. vault kv put <secret-path> url=\"https://loki.example.com\" ..."
        log_info "  2. Add 'loki_url=https://loki.example.com' to deploy.conf"
        log_info "  3. export PROMTAIL_LOKI_URL=https://loki.example.com"
        return 1
    fi
    if [[ -z "${loki_pass}" ]]; then
        log_error "Loki password is not set — Vault retrieval may have failed"
        return 1
    fi

    # Create temp file in the current shell (NOT a subshell) so that the
    # caller can register the trap and the file survives until ansible-playbook finishes.
    PROMTAIL_VARS_FILE=$(mktemp /tmp/promtail_vars_XXXXXX.yml)

    cat > "${PROMTAIL_VARS_FILE}" <<YAML
promtail_loki_url: "${loki_url}"
promtail_basic_auth_user: "${loki_user}"
promtail_basic_auth_password: "${loki_pass}"
YAML
}

# Run the playbook
ansible_run() {
    local check_mode="${1:-}"
    log_header "Running Ansible Playbook${check_mode:+ (check mode)}"
    cd "${ANSIBLE_DIR}" || return 1

    # _create_vars_file sets PROMTAIL_VARS_FILE in the current shell
    _create_vars_file || return 1

    # Ensure cleanup even on unexpected exit
    # shellcheck disable=SC2064
    trap "rm -f '${PROMTAIL_VARS_FILE}'" EXIT

    local extra_args=()
    [[ -n "${check_mode}" ]] && extra_args+=("--check")

    # Password is passed via @file — never on the command line
    log_info "Inventory : inventory.yml"
    log_info "Vars file : ${PROMTAIL_VARS_FILE} (auto-removed after run)"
    [[ -n "${check_mode}" ]] && log_info "Mode      : DRY-RUN (--check)"

    set +e
    ansible-playbook \
        -i inventory.yml \
        playbook.yml \
        -e "@${PROMTAIL_VARS_FILE}" \
        "${extra_args[@]}" \
        2>&1 | tee -a "${LOG_FILE}"
    local rc=${PIPESTATUS[0]}
    set -e

    rm -f "${PROMTAIL_VARS_FILE}"
    # Reset trap
    trap - EXIT

    if [[ ${rc} -eq 0 ]]; then
        log_success "Playbook completed successfully"
    else
        log_error "Playbook failed (exit code ${rc})"
        return "${rc}"
    fi
}

# =============================================================================
# Workflows
# =============================================================================

workflow_run() {
    local start_time
    start_time=$(date +%s)

    check_binaries || return 1
    check_files    || return 1
    vault_initialize || return 1
    ansible_run    || return 1

    local duration=$(( $(date +%s) - start_time ))
    log_header "Deployment Complete"
    log_success "Total time: $((duration / 60))m $((duration % 60))s"
}

workflow_check() {
    check_binaries || return 1
    check_files    || return 1
    vault_initialize || return 1
    ansible_run "--check" || return 1

    log_success "Dry-run complete. No changes were made."
}

workflow_status() {
    check_binaries || return 1
    check_files    || return 1
    ansible_ping   || return 1
}

# =============================================================================
# Interactive menu
# =============================================================================

show_menu() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║     Promtail Remote Install — Deployment             ║"
    echo "║     Ansible + HashiCorp Vault                        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Run playbook  (Vault auth → fetch secret → ansible-playbook)"
    echo -e "  ${BLUE}2)${NC} Dry-run       (--check, no changes applied)"
    echo -e "  ${YELLOW}3)${NC} Status / ping (test connectivity to all hosts)"
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

        case "${choice}" in
            1) workflow_run;    read -r -p "Press Enter to continue..." ;;
            2) workflow_check;  read -r -p "Press Enter to continue..." ;;
            3) workflow_status; read -r -p "Press Enter to continue..." ;;
            0) exit 0 ;;
            *) log_error "Invalid option '${choice}'"; sleep 1 ;;
        esac
    done
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
Usage: $0 [command]

Commands:
  run     - Authenticate to Vault, fetch Loki password, run ansible-playbook
  check   - Same as 'run' but with --check (dry-run, no changes)
  status  - Ping all hosts in inventory.yml
  help    - Show this help

No arguments: interactive menu

Quick start:
  1. Copy and edit the inventory:
       cp inventory.yml.example inventory.yml

  2. Store Loki credentials in Vault:
       vault kv put secret/promtail/loki \\
         url="https://loki.example.com" \\
         username="promtail" \\
         password="<password>"

  3. (Optional) Create deploy.conf to avoid prompts:
       echo 'vault_addr=https://vault.example.com:8200' >> deploy.conf
       echo 'vault_username=operator'                   >> deploy.conf
       echo 'vault_secret_path=secret/promtail/loki'   >> deploy.conf

  4. Run:
       ./deploy.sh run

Environment variable shortcuts:
  VAULT_ADDR                 Vault server URL
  VAULT_USERNAME             Vault userpass username
  VAULT_TOKEN                Existing token (skips login prompt)
  PROMTAIL_VAULT_SECRET_PATH KV path for Loki credentials
  PROMTAIL_LOKI_URL          Override Loki URL from CLI
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_info "Started at $(date)"
    log_info "Log: ${LOG_FILE}"
    echo ""

    if [[ $# -eq 0 ]]; then
        interactive_menu
    else
        case "$1" in
            run)    workflow_run    ;;
            check)  workflow_check  ;;
            status) workflow_status ;;
            help|--help|-h) show_help ;;
            *) log_error "Unknown command: $1"; echo ""; show_help; exit 1 ;;
        esac
    fi

    log_info "Completed at $(date)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
