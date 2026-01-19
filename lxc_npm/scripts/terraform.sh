#!/usr/bin/env bash
# =============================================================================
# Terraform Functions for NPM Deployment
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_TERRAFORM_SH_LOADED:-}" ]] && return 0
_TERRAFORM_SH_LOADED=1

# Get the IaC tool command
_get_tf() {
    get_iac_tool || return 1
}

# -----------------------------------------------------------------------------
# Terraform Operations
# -----------------------------------------------------------------------------

terraform_init() {
    log_info "Initializing Terraform..."
    cd "${TERRAFORM_DIR}" || return 1
    
    local iac_tool
    iac_tool=$(_get_tf) || return 1
    
    local init_args=()
    
    # Check for S3 backend configuration
    if [[ -f "s3.backend.config" ]]; then
        log_info "Using S3 backend configuration"
        init_args+=("-backend-config=s3.backend.config")
    fi
    
    if ${iac_tool} init "${init_args[@]}" | tee -a "${LOG_FILE:-/dev/null}"; then
        log_success "Terraform initialized"
        return 0
    else
        log_error "Terraform init failed"
        return 1
    fi
}

terraform_validate() {
    log_info "Validating Terraform configuration..."
    cd "${TERRAFORM_DIR}" || return 1
    
    local iac_tool
    iac_tool=$(_get_tf) || return 1
    
    if ${iac_tool} validate | tee -a "${LOG_FILE:-/dev/null}"; then
        log_success "Configuration valid"
        return 0
    else
        log_error "Validation failed"
        return 1
    fi
}

terraform_plan() {
    log_info "Creating Terraform plan..."
    cd "${TERRAFORM_DIR}" || return 1
    
    local iac_tool
    iac_tool=$(_get_tf) || return 1
    
    if ${iac_tool} plan -out=tfplan | tee -a "${LOG_FILE:-/dev/null}"; then
        log_success "Plan created: tfplan"
        return 0
    else
        log_error "Plan failed"
        return 1
    fi
}

terraform_apply() {
    log_info "Applying Terraform configuration..."
    cd "${TERRAFORM_DIR}" || return 1
    
    local iac_tool
    iac_tool=$(_get_tf) || return 1
    
    # Use plan file if exists, otherwise auto-approve
    local apply_args=("-auto-approve")
    if [[ -f "tfplan" ]]; then
        apply_args=("tfplan")
    fi
    
    if ${iac_tool} apply "${apply_args[@]}" | tee -a "${LOG_FILE:-/dev/null}"; then
        log_success "Infrastructure deployed"
        rm -f tfplan 2>/dev/null
        return 0
    else
        log_error "Apply failed"
        return 1
    fi
}

terraform_destroy() {
    log_info "Destroying infrastructure..."
    cd "${TERRAFORM_DIR}" || return 1
    
    local iac_tool
    iac_tool=$(_get_tf) || return 1
    
    if confirm "Are you sure you want to destroy all infrastructure?"; then
        if ${iac_tool} destroy -auto-approve | tee -a "${LOG_FILE:-/dev/null}"; then
            log_success "Infrastructure destroyed"
            return 0
        else
            log_error "Destroy failed"
            return 1
        fi
    else
        log_info "Destroy cancelled"
        return 0
    fi
}

terraform_output() {
    cd "${TERRAFORM_DIR}" || return 1
    
    local iac_tool
    iac_tool=$(_get_tf) || return 1
    
    ${iac_tool} output "$@"
}
