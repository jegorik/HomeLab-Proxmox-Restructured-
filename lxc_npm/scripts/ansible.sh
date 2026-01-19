#!/usr/bin/env bash
# =============================================================================
# Ansible Functions for NPM Deployment
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_ANSIBLE_SH_LOADED:-}" ]] && return 0
_ANSIBLE_SH_LOADED=1

# -----------------------------------------------------------------------------
# Ansible Operations
# -----------------------------------------------------------------------------

ansible_create_inventory() {
    log_info "Creating Ansible inventory from Terraform outputs..."
    cd "${TERRAFORM_DIR}" || return 1
    
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    
    local container_ip
    container_ip=$(${iac_tool} output -raw container_ip 2>/dev/null)
    
    if [[ -z "${container_ip}" ]]; then
        log_error "Could not get container IP from Terraform outputs"
        return 1
    fi
    
    local ssh_user
    ssh_user=$(${iac_tool} output -raw ssh_user 2>/dev/null || echo "ansible")
    
    local ssh_port
    ssh_port=$(${iac_tool} output -raw ssh_port 2>/dev/null || echo "22")
    
    cat > "${ANSIBLE_DIR}/inventory.yml" <<EOF
---
all:
  hosts:
    container:
      ansible_host: ${container_ip}
      ansible_user: ${ssh_user}
      ansible_port: ${ssh_port}
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519
      ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF
    
    log_success "Inventory created: ${ANSIBLE_DIR}/inventory.yml"
    log_info "Container IP: ${container_ip}"
    return 0
}

ansible_wait_for_connection() {
    local retries=${1:-30}
    local delay=${2:-2}

    log_info "Waiting for container connectivity (max $((retries * delay))s)..."
    cd "${ANSIBLE_DIR}" || return 1

    local count=0
    while [[ ${count} -lt ${retries} ]]; do
        if ansible all -m ping -i inventory.yml &>/dev/null; then
            log_success "Container is reachable"
            return 0
        fi
        count=$((count + 1))
        sleep ${delay}
    done

    log_error "Timed out waiting for container connectivity"
    return 1
}

ansible_test() {
    log_info "Testing Ansible connectivity..."
    cd "${ANSIBLE_DIR}" || return 1
    
    if ansible all -m ping -i inventory.yml 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        log_success "Container is reachable"
        return 0
    else
        log_error "Cannot reach container"
        return 1
    fi
}

ansible_deploy() {
    log_info "Running Ansible playbook..."
    cd "${ANSIBLE_DIR}" || return 1
    
    if ansible-playbook -i inventory.yml site.yml 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        log_success "Ansible playbook completed"
        return 0
    else
        log_error "Ansible playbook failed"
        return 1
    fi
}
