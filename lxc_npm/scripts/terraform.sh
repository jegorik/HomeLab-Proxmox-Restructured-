#!/usr/bin/env bash
# =============================================================================
# Terraform/OpenTofu Functions for NPM Deployment
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_TERRAFORM_SH_LOADED:-}" ]] && return 0
_TERRAFORM_SH_LOADED=1

# Initialize Terraform
terraform_init() {
    log_header "Initializing Terraform/OpenTofu"
    
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    cd "${TERRAFORM_DIR}" || return 1

    local backend_opt=""
    if [[ -f "s3.backend.config" ]]; then
        backend_opt="-backend-config=s3.backend.config"
        log_info "Using S3 remote state backend"
    else
        log_warning "Using LOCAL state (not recommended for production)"
    fi

    log_info "Running: ${iac_tool} init ${backend_opt}"
    if ${iac_tool} init ${backend_opt} | tee -a "${LOG_FILE}"; then
        log_success "Initialization complete"
        return 0
    else
        log_error "Initialization failed"
        return 1
    fi
}

# Validate configuration
terraform_validate() {
    log_header "Validating Configuration"
    
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    cd "${TERRAFORM_DIR}" || return 1

    if ${iac_tool} validate | tee -a "${LOG_FILE}"; then
        log_success "Configuration valid"
        return 0
    else
        log_error "Validation failed"
        return 1
    fi
}

# Plan changes
terraform_plan() {
    log_header "Planning Changes"
    
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    cd "${TERRAFORM_DIR}" || return 1

    if ${iac_tool} plan -out=tfplan | tee -a "${LOG_FILE}"; then
        log_success "Plan saved to: tfplan"
        return 0
    else
        log_error "Plan failed"
        return 1
    fi
}

# Apply changes
terraform_apply() {
    log_header "Applying Changes"
    
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    cd "${TERRAFORM_DIR}" || return 1

    log_warning "This will create infrastructure on Proxmox"
    confirm "Proceed?" || { log_info "Cancelled"; return 1; }

    if ${iac_tool} apply -auto-approve | tee -a "${LOG_FILE}"; then
        log_success "Apply complete"
        ${iac_tool} output | tee -a "${LOG_FILE}"
        return 0
    else
        log_error "Apply failed"
        return 1
    fi
}

# Destroy infrastructure
terraform_destroy() {
    log_header "Destroying Infrastructure"
    
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    cd "${TERRAFORM_DIR}" || return 1

    log_warning "This will DESTROY all managed infrastructure!"
    confirm "Are you sure?" || { log_info "Cancelled"; return 1; }
    
    echo -e -n "${RED}${BOLD}Type 'destroy' to confirm: ${NC}"
    read -r confirmation
    [[ "${confirmation}" != "destroy" ]] && { log_info "Cancelled"; return 1; }

    if ${iac_tool} destroy -auto-approve -var="vault_password=${TF_VAR_vault_password:-dummy}" | tee -a "${LOG_FILE}"; then
        log_success "Destroy complete"
        return 0
    else
        log_error "Destroy failed"
        return 1
    fi
}

# Get outputs as JSON
terraform_get_outputs() {
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    cd "${TERRAFORM_DIR}" || return 1
    ${iac_tool} output -json 2>/dev/null
}

# Get specific output value
terraform_get_output() {
    local key="$1"
    local iac_tool
    iac_tool=$(get_iac_tool) || return 1
    cd "${TERRAFORM_DIR}" || return 1
    ${iac_tool} output -raw "${key}" 2>/dev/null
}
