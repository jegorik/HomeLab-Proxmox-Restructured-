#!/usr/bin/env bash
# =============================================================================
# NetBox DCIM/IPAM LXC Container - Automated Deployment Script
# =============================================================================
#
# This script automates the deployment, destruction, and validation of the
# NetBox DCIM/IPAM LXC infrastructure on Proxmox using OpenTofu/Terraform
# and Ansible with HashiCorp Vault integration.
#
# Features:
# - HashiCorp Vault integration for secrets management
# - Vault authentication and credential generation (vault_init.sh)
# - Pre-flight checks for all required binaries and files (including vault CLI)
# - Multi-service verification (PostgreSQL, Redis, NetBox, Nginx)
# - Interactive prompts for missing environment variables
# - Terraform/OpenTofu infrastructure provisioning with Vault Transit encryption
# - Ansible configuration management
# - Dry-run/plan mode for validation
# - Safe destruction with confirmations
# - Comprehensive logging and error handling
#
# Prerequisites:
# - HashiCorp Vault deployed and accessible (see lxc_vault project)
# - Vault Transit engine enabled for state encryption
# - Vault KV secrets configured (see DEPLOYMENT.md)
# - Vault userpass authentication enabled
#
# Usage:
#   ./deploy.sh                    # Interactive menu
#   ./deploy.sh deploy             # Full deployment
#   ./deploy.sh destroy            # Destroy infrastructure
#   ./deploy.sh plan               # Dry-run (plan only)
#   ./deploy.sh status             # Check status
#
# Author: HomeLab Infrastructure Team
# Date: January 2026
# =============================================================================

set -o errexit   # Exit on error
set -o nounset   # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# -----------------------------------------------------------------------------
# Configuration Variables
# -----------------------------------------------------------------------------

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Log file with timestamp
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOGS_DIR}/deployment_${TIMESTAMP}.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Status tracking
TERRAFORM_APPLIED=false
ANSIBLE_APPLIED=false

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

# Print colored output with logging
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} ${message}" | tee -a "${LOG_FILE}"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} ${message}" | tee -a "${LOG_FILE}"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} ${message}" | tee -a "${LOG_FILE}"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "${LOG_FILE}"
}

log_header() {
    local message="$1"
    echo -e "\n${BOLD}${CYAN}========================================${NC}" | tee -a "${LOG_FILE}"
    echo -e "${BOLD}${CYAN}${message}${NC}" | tee -a "${LOG_FILE}"
    echo -e "${BOLD}${CYAN}========================================${NC}\n" | tee -a "${LOG_FILE}"
}

# Print section separator
print_separator() {
    echo -e "${CYAN}----------------------------------------${NC}" | tee -a "${LOG_FILE}"
}

# Ask for user confirmation
confirm() {
    local prompt="$1"
    local response

    while true; do
        echo -e -n "${YELLOW}${prompt} (yes/no): ${NC}"
        read -r response
        case "${response}" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo -e "${RED}Please answer 'yes' or 'no'${NC}"
                ;;
        esac
    done
}

# Progress indicator for long-running operations
show_progress() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0

    echo -n "${message} "
    while kill -0 "${pid}" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r${message} ${spin:$i:1}"
        sleep 0.1
    done
    printf "\r${message} ${GREEN}✓${NC}\n"
}

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------

# Create logs directory if it doesn't exist
create_logs_dir() {
    if [[ ! -d "${LOGS_DIR}" ]]; then
        mkdir -p "${LOGS_DIR}"
        log_info "Created logs directory: ${LOGS_DIR}"
    fi
}

# Check if a command exists
check_command() {
    local cmd="$1"
    local package_hint="${2:-}"

    if command -v "${cmd}" &> /dev/null; then
        local version
        case "${cmd}" in
            tofu)
                version=$(tofu version | head -n1 | awk '{print $2}')
                ;;
            terraform)
                version=$(terraform version | head -n1 | awk '{print $2}')
                ;;
            ansible)
                version=$(ansible --version | head -n1 | awk '{print $2}')
                ;;
            aws)
                version=$(aws --version | awk '{print $1}' | cut -d'/' -f2)
                ;;
            *)
                version="installed"
                ;;
        esac
        log_success "Found ${cmd}: ${version}"
        return 0
    else
        log_error "Missing required command: ${cmd}"
        if [[ -n "${package_hint}" ]]; then
            log_info "Install with: ${package_hint}"
        fi
        return 1
    fi
}

# Check all required binaries
check_binaries() {
    log_header "Checking Required Binaries"

    local all_found=true

    # Check for OpenTofu or Terraform
    if ! check_command "tofu" "curl -Lo /tmp/tofu.zip https://github.com/opentofu/opentofu/releases/latest/download/tofu_*_linux_amd64.zip && unzip /tmp/tofu.zip -d /tmp && sudo mv /tmp/tofu /usr/local/bin/"; then
        if ! check_command "terraform" "curl -Lo /tmp/terraform.zip https://releases.hashicorp.com/terraform/latest/terraform_*_linux_amd64.zip && unzip /tmp/terraform.zip -d /tmp && sudo mv /tmp/terraform /usr/local/bin/"; then
            log_error "Neither OpenTofu nor Terraform found. At least one is required."
            all_found=false
        fi
    fi

    # Check for Ansible
    if ! check_command "ansible" "pip install ansible"; then
        all_found=false
    fi

    if ! check_command "ansible-playbook" "pip install ansible"; then
        all_found=false
    fi

    # Check for SSH
    if ! check_command "ssh" "sudo apt-get install openssh-client"; then
        all_found=false
    fi

    # Check for AWS CLI (optional for S3 backend)
    if ! check_command "aws" "pip install awscli"; then
        log_warning "AWS CLI not found - S3 backend state storage will not be available"
    fi

    # Check for other utilities
    check_command "git" "sudo apt-get install git" || all_found=false
    check_command "jq" "sudo apt-get install jq" || all_found=false

    # Check for Vault CLI (required for NetBox deployment)
    if ! check_command "vault" "curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - && echo 'deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main' | sudo tee /etc/apt/sources.list.d/hashicorp.list && sudo apt-get update && sudo apt-get install vault"; then
        log_error "Vault CLI is required for NetBox deployment"
        all_found=false
    fi

    if [[ "${all_found}" == false ]]; then
        log_error "Some required binaries are missing. Please install them and try again."
        return 1
    fi

    log_success "All required binaries found"
    return 0
}

# Check if required directories exist
check_directories() {
    log_header "Checking Project Structure"

    local all_exist=true

    if [[ ! -d "${TERRAFORM_DIR}" ]]; then
        log_error "Terraform directory not found: ${TERRAFORM_DIR}"
        all_exist=false
    else
        log_success "Found Terraform directory"
    fi

    if [[ ! -d "${ANSIBLE_DIR}" ]]; then
        log_error "Ansible directory not found: ${ANSIBLE_DIR}"
        all_exist=false
    else
        log_success "Found Ansible directory"
    fi

    if [[ "${all_exist}" == false ]]; then
        log_error "Required directories missing. Please check project structure."
        return 1
    fi

    return 0
}

# Check for required Terraform files
check_terraform_files() {
    log_header "Checking Terraform Configuration"

    local critical_missing=false

    # Check for critical files
    local critical_files=("main.tf" "variables.tf" "providers.tf" "backend.tf")
    for file in "${critical_files[@]}"; do
        if [[ ! -f "${TERRAFORM_DIR}/${file}" ]]; then
            log_error "Missing critical file: ${file}"
            critical_missing=true
        else
            log_success "Found ${file}"
        fi
    done

    if [[ "${critical_missing}" == true ]]; then
        return 1
    fi

    # Check for terraform.tfvars (warn if missing)
    if [[ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
        log_warning "terraform.tfvars not found"
        if [[ -f "${TERRAFORM_DIR}/terraform.tfvars.example" ]]; then
            log_info "Example file exists: terraform.tfvars.example"
            if confirm "Would you like to create terraform.tfvars from the example?"; then
                cp "${TERRAFORM_DIR}/terraform.tfvars.example" "${TERRAFORM_DIR}/terraform.tfvars"
                log_success "Created terraform.tfvars from example"
                log_warning "Please edit terraform.tfvars with your configuration before proceeding"
                return 1
            fi
        fi
        log_warning "You will need to provide all variables via environment or command line"
    else
        log_success "Found terraform.tfvars"
    fi

    return 0
}

# Check for S3 backend configuration
check_s3_backend() {
    log_header "Checking S3 Backend Configuration"

    if [[ ! -f "${TERRAFORM_DIR}/s3.backend.config" ]]; then
        log_warning "s3.backend.config not found - S3 backend will not be used"

        if [[ -f "${TERRAFORM_DIR}/s3.backend.config.template" ]]; then
            log_info "Template file exists: s3.backend.config.template"
            if confirm "Would you like to create s3.backend.config from the template?"; then
                cp "${TERRAFORM_DIR}/s3.backend.config.template" "${TERRAFORM_DIR}/s3.backend.config"
                log_success "Created s3.backend.config from template"
                log_warning "Please edit s3.backend.config with your AWS configuration"
                log_info "You can also proceed with local state storage (not recommended for production)"
                return 1
            fi
        fi

        log_warning "Proceeding with LOCAL state storage"
        log_warning "This is NOT recommended for production environments!"
        log_info "State file will be stored locally in: ${TERRAFORM_DIR}/terraform.tfstate"

        return 2  # Return 2 to indicate local state
    else
        log_success "Found s3.backend.config - will use S3 remote state"

        # Check if AWS CLI is configured
        if command -v aws &> /dev/null; then
            if aws sts get-caller-identity &> /dev/null; then
                log_success "AWS credentials are configured"
            else
                log_warning "AWS credentials may not be configured correctly"
                log_info "Run: aws configure --profile <your-profile>"
            fi
        fi

        return 0
    fi
}

# Check SSH keys
check_ssh_keys() {
    log_header "Checking SSH Keys"

    local keys_ok=true

    # Common SSH key locations
    local default_keys=(
        "${HOME}/.ssh/id_rsa"
        "${HOME}/.ssh/id_ed25519"
        "${HOME}/.ssh/pve_ssh"
        "${HOME}/.ssh/ansible"
    )

    local found_keys=()
    for key in "${default_keys[@]}"; do
        if [[ -f "${key}" ]]; then
            found_keys+=("${key}")
            log_success "Found SSH key: ${key}"
        fi
    done

    if [[ ${#found_keys[@]} -eq 0 ]]; then
        log_warning "No SSH keys found in common locations"
        log_info "You may need to generate SSH keys:"
        log_info "  ssh-keygen -t ed25519 -C 'vault-deployment' -f ~/.ssh/pve_ssh"
        log_info "  ssh-keygen -t ed25519 -C 'ansible' -f ~/.ssh/ansible"
        keys_ok=false
    fi

    return 0
}

# Check Vault connectivity and authentication
check_vault_connection() {
    log_header "Checking HashiCorp Vault Connection"

    # Check if VAULT_ADDR is set
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        log_warning "VAULT_ADDR not set"
        log_info "Default: https://vault.example.com:8200"
        
        # Check if vault_init.sh exists
        if [[ -f "${TERRAFORM_DIR}/vault_init.sh" ]]; then
            log_info "vault_init.sh found - will be sourced during deployment"
        else
            log_warning "vault_init.sh not found"
            if [[ -f "${TERRAFORM_DIR}/vault_init.sh.example" ]]; then
                log_info "Example file exists: vault_init.sh.example"
                if confirm "Would you like to create vault_init.sh from the example?"; then
                    cp "${TERRAFORM_DIR}/vault_init.sh.example" "${TERRAFORM_DIR}/vault_init.sh"
                    chmod +x "${TERRAFORM_DIR}/vault_init.sh"
                    log_success "Created vault_init.sh from example"
                    log_warning "Please edit vault_init.sh with your Vault configuration"
                fi
            fi
        fi
        return 1
    fi

    log_success "VAULT_ADDR set: ${VAULT_ADDR}"

    # Test Vault connectivity
    if command -v vault &> /dev/null; then
        if vault status &> /dev/null 2>&1; then
            log_success "Vault is accessible and unsealed"
        elif curl -sk "${VAULT_ADDR}/v1/sys/health" &> /dev/null; then
            log_warning "Vault is accessible but may be sealed or unauthenticated"
            log_info "Vault authentication will be handled by vault_init.sh during deployment"
        else
            log_error "Cannot connect to Vault at ${VAULT_ADDR}"
            log_info "Please ensure Vault is running and accessible"
            return 1
        fi
    else
        log_error "vault CLI not found"
        return 1
    fi

    # Check if vault_init.sh exists for authentication
    if [[ -f "${TERRAFORM_DIR}/vault_init.sh" ]]; then
        log_success "Found vault_init.sh for Vault authentication"
    else
        log_warning "vault_init.sh not found - manual Vault authentication required"
        log_info "You'll need to authenticate with Vault before deployment:"
        log_info "  export VAULT_ADDR='https://vault.example.com:8200'"
        log_info "  vault login -method=userpass username=terraform"
    fi

    return 0
}

# Check for encryption passphrase (not used in NetBox - uses Vault Transit)
check_encryption_passphrase() {
    log_header "Checking State Encryption Configuration"

    log_info "NetBox uses Vault Transit engine for state encryption"
    log_info "Checking Vault Transit configuration..."

    if [[ -z "${VAULT_ADDR:-}" ]]; then
        log_warning "VAULT_ADDR not set - Vault Transit encryption not configured"
        log_info "State encryption will be configured during Vault authentication"
        return 1
    fi

    log_success "State encryption will use Vault Transit engine"
    log_info "Transit path: ${TF_VAR_transit_engine_path:-transit}"
    log_info "Key name: ${TF_VAR_transit_key_name:-terraform-state-encryption}"

    # Note: Actual Transit engine verification happens during vault_init.sh
    return 0
}

# Source vault_init.sh for Vault authentication
source_vault_init() {
    log_header "Vault Authentication"

    if [[ ! -f "${TERRAFORM_DIR}/vault_init.sh" ]]; then
        log_error "vault_init.sh not found: ${TERRAFORM_DIR}/vault_init.sh"
        log_info "This script handles Vault authentication and AWS credentials"
        log_info "Please create vault_init.sh from vault_init.sh.example"
        return 1
    fi

    log_info "Sourcing vault_init.sh for Vault authentication..."
    
    cd "${TERRAFORM_DIR}" || return 1
    
    # Source the vault_init.sh script
    if source ./vault_init.sh; then
        log_success "Vault authentication completed successfully"
        log_info "VAULT_TOKEN set: ${VAULT_TOKEN:0:10}..."
        if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
            log_success "AWS credentials generated from Vault"
        fi
        return 0
    else
        log_error "Vault authentication failed"
        log_info "Please check your Vault credentials and try again"
        return 1
    fi
}

# Verify Vault secrets exist
check_vault_secrets() {
    log_header "Checking Required Vault Secrets"

    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "VAULT_TOKEN not set - skipping secret verification"
        log_info "Secrets will be verified during deployment"
        return 0
    fi

    local required_secrets=(
        "secrets/data/proxmox/api_token"
        "secrets/data/proxmox/ssh_keys/root_public"
        "secrets/data/proxmox/ssh_keys/ansible_public"
        "secrets/data/proxmox/node_name"
    )

    local all_exist=true
    for secret_path in "${required_secrets[@]}"; do
        if vault kv get "${secret_path}" &> /dev/null; then
            log_success "Found secret: ${secret_path}"
        else
            log_error "Missing secret: ${secret_path}"
            all_exist=false
        fi
    done

    if [[ "${all_exist}" == false ]]; then
        log_error "Some required secrets are missing in Vault"
        log_info "Please store the required secrets before deployment"
        log_info "See DEPLOYMENT.md for details"
        return 1
    fi

    log_success "All required Vault secrets found"
    return 0
}

# Old passphrase check (kept for compatibility but logs different message)
check_old_encryption_passphrase() {
    log_header "Legacy State Encryption Check"

    local passphrase_file="${HOME}/.ssh/state_passphrase"

    if [[ -f "${passphrase_file}" ]]; then
        log_warning "Found legacy passphrase file: ${passphrase_file}"
        log_info "NetBox uses Vault Transit engine instead of passphrase-based encryption"
        log_info "The passphrase file is not needed for this project"
    else
        log_info "No legacy passphrase file found (expected for NetBox)"
        log_success "NetBox will use Vault Transit for state encryption"
    fi

    return 0
}

# Wrapper for original function name compatibility
old_check_encryption_passphrase() {
    local passphrase_file="${HOME}/.ssh/state_passphrase"

    if [[ ! -f "${passphrase_file}" ]]; then
        log_info "State encryption uses Vault Transit engine (no passphrase needed)"
        return 0
    else
        # Check file permissions
        local perms=$(stat -c "%a" "${passphrase_file}" 2>/dev/null || stat -f "%p" "${passphrase_file}" 2>/dev/null | tail -c 4)
        if [[ "${perms}" != "600" ]]; then
            log_warning "Legacy passphrase file has insecure permissions: ${perms}"
            log_info "Fixing permissions..."
            chmod 600 "${passphrase_file}"
            log_success "Set permissions to 600"
        else
            log_success "Found state encryption passphrase with correct permissions"
        fi
    fi

    return 0
}

# Check .gitignore for sensitive files
check_gitignore() {
    log_header "Checking .gitignore Configuration"

    local gitignore="${SCRIPT_DIR}/.gitignore"

    if [[ ! -f "${gitignore}" ]]; then
        log_warning ".gitignore not found - sensitive files may be committed!"
        return 1
    fi

    # Critical patterns that should be in .gitignore
    local critical_patterns=(
        "*.tfstate"
        "*.tfvars"
        "*password*"
        "*secret*"
        "s3.backend.config"
    )

    local missing_patterns=()
    for pattern in "${critical_patterns[@]}"; do
        if ! grep -q "${pattern}" "${gitignore}"; then
            missing_patterns+=("${pattern}")
        fi
    done

    if [[ ${#missing_patterns[@]} -gt 0 ]]; then
        log_warning "Some critical patterns missing from .gitignore:"
        for pattern in "${missing_patterns[@]}"; do
            log_warning "  - ${pattern}"
        done
    else
        log_success ".gitignore properly configured"
    fi

    return 0
}

# Check Ansible inventory
check_ansible_inventory() {
    log_header "Checking Ansible Inventory"

    if [[ ! -f "${ANSIBLE_DIR}/inventory.yml" ]]; then
        log_warning "Ansible inventory not found: inventory.yml"

        if [[ -f "${ANSIBLE_DIR}/inventory.yml.example" ]]; then
            log_info "Example file exists: inventory.yml.example"
            log_info "After Terraform deployment, you'll need to create inventory.yml"
            log_info "with the container IP address from Terraform outputs"
        fi

        return 1
    else
        log_success "Found Ansible inventory.yml"
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Environment Variable Management
# -----------------------------------------------------------------------------

# Get or prompt for environment variable
get_or_prompt_var() {
    local var_name="$1"
    local prompt_message="$2"
    local is_secret="${3:-false}"
    local file_path="${4:-}"

    # Check if environment variable is already set
    if [[ -n "${!var_name:-}" ]]; then
        log_success "Using existing environment variable: ${var_name}"
        return 0
    fi

    # Check if file-based credential exists
    if [[ -n "${file_path}" && -f "${file_path}" ]]; then
        local file_content
        file_content=$(cat "${file_path}")
        export "${var_name}=${file_content}"
        log_success "Loaded ${var_name} from file: ${file_path}"
        return 0
    fi

    # Prompt user for input
    log_warning "${var_name} is not set"
    echo -e -n "${YELLOW}${prompt_message}: ${NC}"

    if [[ "${is_secret}" == "true" ]]; then
        read -rs input_value
        echo  # New line after hidden input
    else
        read -r input_value
    fi

    if [[ -z "${input_value}" ]]; then
        log_error "No value provided for ${var_name}"
        return 1
    fi

    export "${var_name}=${input_value}"
    log_success "Set ${var_name} from user input"

    return 0
}

# Check and set required environment variables
check_environment_variables() {
    log_header "Checking Environment Variables"

    local all_set=true

    # Check for Proxmox root password (critical for bind mounts)
    local pve_password_file="${HOME}/.ssh/pve_root_password"
    if ! get_or_prompt_var "TF_VAR_pve_root_password" \
        "Enter Proxmox root@pam password" \
        "true" \
        "${pve_password_file}"; then
        all_set=false
    fi

    # Check for Proxmox endpoint
    if ! get_or_prompt_var "TF_VAR_proxmox_endpoint" \
        "Enter Proxmox API endpoint (e.g., https://192.168.1.100:8006)" \
        "false" \
        ""; then
        log_info "You can also set this in terraform.tfvars"
    fi

    # Check for Proxmox API token (optional if using password)
    if [[ -z "${TF_VAR_proxmox_api_token:-}" ]]; then
        log_info "TF_VAR_proxmox_api_token not set (using root@pam password instead)"
        log_info "This is normal for deployments using bind mounts"
    fi

    # Check for state encryption passphrase
    local passphrase_file="${HOME}/.ssh/state_passphrase"
    if [[ -f "${passphrase_file}" ]]; then
        if [[ -z "${TF_VAR_passphrase:-}" ]]; then
            export TF_VAR_passphrase="${passphrase_file}"
            log_success "Set TF_VAR_passphrase to: ${passphrase_file}"
        fi
    fi

    log_success "Environment variables configured"
    return 0
}

# -----------------------------------------------------------------------------
# Terraform/OpenTofu Operations
# -----------------------------------------------------------------------------

# Determine which IaC tool to use
get_iac_tool() {
    if command -v tofu &> /dev/null; then
        echo "tofu"
    elif command -v terraform &> /dev/null; then
        echo "terraform"
    else
        log_error "Neither OpenTofu nor Terraform found"
        return 1
    fi
}

# Initialize Terraform/OpenTofu
terraform_init() {
    log_header "Initializing Terraform/OpenTofu"

    local iac_tool
    iac_tool=$(get_iac_tool)

    cd "${TERRAFORM_DIR}" || return 1

    # Check for S3 backend
    local backend_option=""
    check_s3_backend
    local backend_status=$?

    if [[ ${backend_status} -eq 0 ]]; then
        # S3 backend available
        backend_option="-backend-config=s3.backend.config"
        log_info "Initializing with S3 remote state backend..."
    elif [[ ${backend_status} -eq 2 ]]; then
        # Local state
        log_warning "Initializing with LOCAL state storage..."
    fi

    log_info "Running: ${iac_tool} init ${backend_option}"

    if ${iac_tool} init ${backend_option} | tee -a "${LOG_FILE}"; then
        log_success "Terraform/OpenTofu initialized successfully"
        return 0
    else
        log_error "Terraform/OpenTofu initialization failed"
        return 1
    fi
}

# Validate Terraform configuration
terraform_validate() {
    log_header "Validating Terraform Configuration"

    local iac_tool
    iac_tool=$(get_iac_tool)

    cd "${TERRAFORM_DIR}" || return 1

    log_info "Running: ${iac_tool} validate"

    if ${iac_tool} validate | tee -a "${LOG_FILE}"; then
        log_success "Terraform configuration is valid"
        return 0
    else
        log_error "Terraform validation failed"
        return 1
    fi
}

# Plan Terraform changes
terraform_plan() {
    log_header "Planning Terraform Changes"

    local iac_tool
    iac_tool=$(get_iac_tool)

    cd "${TERRAFORM_DIR}" || return 1

    log_info "Running: ${iac_tool} plan"

    if ${iac_tool} plan -out=tfplan | tee -a "${LOG_FILE}"; then
        log_success "Terraform plan completed successfully"
        log_info "Plan saved to: tfplan"
        return 0
    else
        log_error "Terraform plan failed"
        return 1
    fi
}

# Apply Terraform changes
terraform_apply() {
    log_header "Applying Terraform Changes"

    local iac_tool
    iac_tool=$(get_iac_tool)

    cd "${TERRAFORM_DIR}" || return 1

    log_info "Running: ${iac_tool} apply"
    log_warning "This will create infrastructure on your Proxmox host"

    if ! confirm "Proceed with Terraform apply?"; then
        log_info "Terraform apply cancelled by user"
        return 1
    fi

    if ${iac_tool} apply -auto-approve | tee -a "${LOG_FILE}"; then
        log_success "Terraform applied successfully"
        TERRAFORM_APPLIED=true

        # Display outputs
        print_separator
        log_info "Terraform Outputs:"
        ${iac_tool} output | tee -a "${LOG_FILE}"
        print_separator

        return 0
    else
        log_error "Terraform apply failed"
        log_error "Infrastructure may be in an inconsistent state"
        log_info "Check the logs and run 'terraform destroy' if needed"
        return 1
    fi
}

# Destroy Terraform infrastructure
terraform_destroy() {
    log_header "Destroying Terraform Infrastructure"

    local iac_tool
    iac_tool=$(get_iac_tool)

    cd "${TERRAFORM_DIR}" || return 1

    log_warning "This will DESTROY all infrastructure managed by Terraform!"
    log_warning "This includes:"
    log_warning "  - LXC container"
    log_warning "  - All container data"
    log_warning "  - Network configuration"

    if ! confirm "Are you absolutely sure you want to destroy the infrastructure?"; then
        log_info "Destroy cancelled by user"
        return 1
    fi

    # Double confirmation for safety
    echo -e -n "${RED}${BOLD}Type 'destroy' to confirm: ${NC}"
    read -r confirmation

    if [[ "${confirmation}" != "destroy" ]]; then
        log_info "Destroy cancelled - confirmation did not match"
        return 1
    fi

    log_info "Running: ${iac_tool} destroy"

    if ${iac_tool} destroy -auto-approve | tee -a "${LOG_FILE}"; then
        log_success "Infrastructure destroyed successfully"
        return 0
    else
        log_error "Terraform destroy failed"
        log_error "Some resources may still exist"
        log_info "Check Proxmox web UI and logs for details"
        return 1
    fi
}

# Get Terraform outputs
get_terraform_outputs() {
    local iac_tool
    iac_tool=$(get_iac_tool)

    cd "${TERRAFORM_DIR}" || return 1

    if ${iac_tool} output -json > /tmp/tf_outputs.json 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Ansible Operations
# -----------------------------------------------------------------------------

# Test Ansible connectivity
ansible_test() {
    log_header "Testing Ansible Connectivity"

    cd "${ANSIBLE_DIR}" || return 1

    if [[ ! -f "inventory.yml" ]]; then
        log_error "Ansible inventory.yml not found"
        log_info "Please create inventory.yml with the container IP from Terraform output"
        return 1
    fi

    log_info "Running: ansible netbox -m ping -i inventory.yml"

    if ansible netbox -m ping -i inventory.yml | tee -a "${LOG_FILE}"; then
        log_success "Ansible connectivity test passed"
        return 0
    else
        log_error "Ansible connectivity test failed"
        log_info "Make sure:"
        log_info "  1. Container is running"
        log_info "  2. SSH keys are configured"
        log_info "  3. inventory.yml has correct IP address"
        return 1
    fi
}

# Run Ansible playbook
ansible_deploy() {
    log_header "Running Ansible Playbook"

    cd "${ANSIBLE_DIR}" || return 1

    if [[ ! -f "inventory.yml" ]]; then
        log_error "Ansible inventory.yml not found"
        log_info "Creating inventory.yml from Terraform outputs..."

        if ! create_ansible_inventory; then
            log_error "Failed to create Ansible inventory"
            return 1
        fi
    fi

    log_info "Running: ansible-playbook -i inventory.yml site.yml"

    if ansible-playbook -i inventory.yml site.yml | tee -a "${LOG_FILE}"; then
        log_success "Ansible playbook completed successfully"
        ANSIBLE_APPLIED=true
        return 0
    else
        log_error "Ansible playbook failed"
        log_error "Vault configuration may be incomplete"
        log_info "Check the logs for details"
        log_info "You can re-run the playbook manually: cd ansible && ansible-playbook -i inventory.yml site.yml"
        return 1
    fi
}

# Create Ansible inventory from Terraform outputs
create_ansible_inventory() {
    local iac_tool
    iac_tool=$(get_iac_tool)

    cd "${TERRAFORM_DIR}" || return 1

    local container_ip
    # Try multiple output names for compatibility
    container_ip=$(${iac_tool} output -raw lxc_ip_address 2>/dev/null || ${iac_tool} output -raw vault_ip_address 2>/dev/null)

    if [[ -z "${container_ip}" || "${container_ip}" == "null" ]]; then
        log_error "Could not get container IP from Terraform outputs"
        log_info "Available outputs:"
        ${iac_tool} output 2>&1 | grep -E "^[a-z_]+" | head -5
        return 1
    fi

    # Strip CIDR notation if present (e.g., 192.168.0.103/24 -> 192.168.0.103)
    container_ip="${container_ip%%/*}"

    log_info "Container IP: ${container_ip}"

    cat > "${ANSIBLE_DIR}/inventory.yml" << EOF
# =============================================================================
# Ansible Inventory - Generated by deploy.sh
# =============================================================================
# Generated: $(date)
# Container IP: ${container_ip}
# =============================================================================

all:
  children:
    netbox:
      hosts:
        netbox-server:
          ansible_host: ${container_ip}
          ansible_port: 22
          ansible_user: ansible
          ansible_ssh_private_key_file: ~/.ssh/ansible
          ansible_python_interpreter: /usr/bin/python3
      vars:
        ansible_become: true
        ansible_become_method: sudo
EOF

    log_success "Created Ansible inventory: ${ANSIBLE_DIR}/inventory.yml"
    return 0
}

# -----------------------------------------------------------------------------
# Main Deployment Functions
# -----------------------------------------------------------------------------

# Full deployment workflow
deploy_infrastructure() {
    log_header "Starting Full Infrastructure Deployment"

    local start_time
    start_time=$(date +%s)

    # Pre-flight checks
    if ! check_binaries; then
        log_error "Pre-flight binary checks failed"
        return 1
    fi

    if ! check_directories; then
        log_error "Pre-flight directory checks failed"
        return 1
    fi

    if ! check_terraform_files; then
        log_error "Terraform configuration check failed"
        log_info "Please configure terraform.tfvars and try again"
        return 1
    fi

    check_s3_backend
    check_ssh_keys
    check_vault_connection  # Check Vault connection for NetBox
    check_encryption_passphrase  # Uses Vault Transit
    check_gitignore

    if ! check_environment_variables; then
        log_error "Environment variable checks failed"
        return 1
    fi

    # Authenticate with Vault (required for NetBox)
    log_header "Vault Authentication (Required)"
    if ! source_vault_init; then
        log_error "Vault authentication failed"
        log_info "NetBox requires Vault for secrets management and state encryption"
        log_info "Please ensure:"
        log_info "  1. Vault is running and accessible"
        log_info "  2. vault_init.sh is configured correctly"
        log_info "  3. You have valid Vault credentials"
        return 1
    fi

    # Terraform workflow
    if ! terraform_init; then
        log_error "Terraform initialization failed"
        return 1
    fi

    if ! terraform_validate; then
        log_error "Terraform validation failed"
        return 1
    fi

    if ! terraform_apply; then
        log_error "Terraform apply failed"
        return 1
    fi

    # Wait for container to be ready
    log_info "Waiting 30 seconds for container to fully boot..."
    sleep 30

    # Create Ansible inventory from Terraform outputs
    if ! create_ansible_inventory; then
        log_warning "Failed to create Ansible inventory automatically"
        log_info "Please create ansible/inventory.yml manually and run ansible playbook"
        return 1
    fi

    # Test Ansible connectivity
    log_info "Testing Ansible connectivity (retrying up to 3 times)..."
    local retry_count=0
    while [[ ${retry_count} -lt 3 ]]; do
        if ansible_test; then
            break
        fi
        retry_count=$((retry_count + 1))
        if [[ ${retry_count} -lt 3 ]]; then
            log_warning "Retry ${retry_count}/3 in 10 seconds..."
            sleep 10
        fi
    done

    if [[ ${retry_count} -eq 3 ]]; then
        log_error "Ansible connectivity test failed after 3 retries"
        log_info "Infrastructure is deployed but not configured"
        log_info "You can manually run: cd ansible && ansible-playbook site.yml"
        return 1
    fi

    # Run Ansible playbook
    if ! ansible_deploy; then
        log_error "Ansible deployment failed"
        log_info "Infrastructure is deployed but Vault configuration is incomplete"
        return 1
    fi

    # Calculate deployment time
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Deployment summary
    print_deployment_summary "${duration}"

    return 0
}

# Dry-run (plan only)
dry_run_deployment() {
    log_header "Running Dry-Run (Plan Only)"

    # Pre-flight checks
    if ! check_binaries; then
        log_error "Pre-flight binary checks failed"
        return 1
    fi

    if ! check_directories; then
        log_error "Pre-flight directory checks failed"
        return 1
    fi

    if ! check_terraform_files; then
        log_error "Terraform configuration check failed"
        return 1
    fi

    check_s3_backend
    check_environment_variables

    # Terraform workflow (plan only)
    if ! terraform_init; then
        log_error "Terraform initialization failed"
        return 1
    fi

    if ! terraform_validate; then
        log_error "Terraform validation failed"
        return 1
    fi

    if ! terraform_plan; then
        log_error "Terraform plan failed"
        return 1
    fi

    log_success "Dry-run completed successfully"
    log_info "No infrastructure was created"
    log_info "To apply changes, run: ./deploy.sh deploy"

    return 0
}

# Destroy infrastructure
destroy_infrastructure() {
    log_header "Destroying Infrastructure"

    if ! check_binaries; then
        log_error "Pre-flight binary checks failed"
        return 1
    fi

    if ! check_directories; then
        log_error "Pre-flight directory checks failed"
        return 1
    fi

    check_environment_variables

    # Terraform destroy
    if ! terraform_destroy; then
        log_error "Infrastructure destruction failed"
        return 1
    fi

    log_success "Infrastructure destroyed successfully"

    # Clean up generated files
    if [[ -f "${ANSIBLE_DIR}/inventory.yml" ]]; then
        if confirm "Remove generated Ansible inventory.yml?"; then
            rm "${ANSIBLE_DIR}/inventory.yml"
            log_success "Removed inventory.yml"
        fi
    fi

    return 0
}

# Check deployment status
check_deployment_status() {
    log_header "Checking Deployment Status"

    local iac_tool
    iac_tool=$(get_iac_tool)

    cd "${TERRAFORM_DIR}" || return 1

    # Check if Terraform state exists
    if [[ ! -f "terraform.tfstate" && ! -f ".terraform/terraform.tfstate" ]]; then
        log_info "No Terraform state found - infrastructure not deployed"
        return 0
    fi

    log_info "Terraform State Information:"
    print_separator

    # Get Terraform outputs
    if get_terraform_outputs; then
        log_success "Infrastructure is deployed"

        # Display key outputs
        if command -v jq &> /dev/null; then
            local netbox_url
            netbox_url=$(jq -r '.netbox_url.value // "N/A"' /tmp/tf_outputs.json)
            log_info "NetBox URL: ${netbox_url}"

            local container_ip
            # Try both output names and strip CIDR notation
            container_ip=$(jq -r '.lxc_ip_address.value // .netbox_ip_address.value // "N/A"' /tmp/tf_outputs.json)
            container_ip="${container_ip%%/*}"  # Strip /24 if present
            log_info "Container IP: ${container_ip}"

            local ssh_command
            ssh_command=$(jq -r '.ssh_command.value // "N/A"' /tmp/tf_outputs.json)
            log_info "SSH Command: ${ssh_command}"
        fi

        print_separator

        # Check if NetBox is accessible
        local container_ip
        container_ip=$(${iac_tool} output -raw lxc_ip_address 2>/dev/null | cut -d'/' -f1)

        if [[ -n "${container_ip}" ]]; then
            log_info "Testing NetBox services accessibility..."
            
            # Test port 80 first, then 8300
            if curl -s -o /dev/null -w "%{http_code}" "http://${container_ip}/" | grep -q "200\|301\|302"; then
                log_success "NetBox is accessible at http://${container_ip}/"
            elif curl -s -o /dev/null -w "%{http_code}" "http://${container_ip}:8300/" | grep -q "200\|301\|302"; then
                log_success "NetBox is accessible at http://${container_ip}:8300/"
            else
                log_warning "NetBox may not be accessible yet (services may still be starting)"
            fi
        fi
    else
        log_warning "Could not read Terraform outputs"
    fi

    # Check Ansible inventory
    if [[ -f "${ANSIBLE_DIR}/inventory.yml" ]]; then
        log_success "Ansible inventory exists"

        # Test connectivity
        cd "${ANSIBLE_DIR}" || return 1
        if ansible netbox -m ping -i inventory.yml &> /dev/null; then
            log_success "Ansible connectivity: OK"
            
            # Check NetBox services if container is accessible
            log_info "Checking NetBox services status..."
            local services=("postgresql" "redis-server" "netbox" "netbox-rq" "nginx")
            local all_running=true
            
            for service in "${services[@]}"; do
                if ansible netbox -i inventory.yml -m shell -a "systemctl is-active ${service}" -b &> /dev/null; then
                    log_success "  ${service}: running"
                else
                    log_warning "  ${service}: not running or not installed"
                    all_running=false
                fi
            done
            
            if [[ "${all_running}" == true ]]; then
                log_success "All NetBox services are running"
            fi
        else
            log_warning "Ansible connectivity: FAILED"
        fi
    else
        log_warning "Ansible inventory not found"
    fi

    return 0
}

# Print deployment summary
print_deployment_summary() {
    local duration=$1
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    log_header "Deployment Summary"

    echo -e "${GREEN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}  ${BOLD}Deployment Completed Successfully!${NC}                        ${GREEN}│${NC}"
    echo -e "${GREEN}├─────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${GREEN}│${NC}  Deployment Time: ${minutes}m ${seconds}s                                   ${GREEN}│${NC}"
    echo -e "${GREEN}│${NC}  Terraform Applied: ${TERRAFORM_APPLIED}                                ${GREEN}│${NC}"
    echo -e "${GREEN}│${NC}  Ansible Applied: ${ANSIBLE_APPLIED}                                  ${GREEN}│${NC}"
    echo -e "${GREEN}└─────────────────────────────────────────────────────────────┘${NC}"

    echo ""
    log_info "Next Steps:"
    echo ""
    echo -e "  ${CYAN}1.${NC} Access NetBox web interface:"
    echo -e "     ${YELLOW}Open browser to container IP (port 80 or 8300)${NC}"
    echo ""
    echo -e "  ${CYAN}2.${NC} Retrieve admin password from Vault:"
    echo -e "     ${YELLOW}vault kv get secrets/proxmox/netbox${NC}"
    echo ""
    echo -e "  ${CYAN}3.${NC} Verify all services are running:"
    echo -e "     ${YELLOW}ssh ansible@<container-ip>${NC}"
    echo -e "     ${YELLOW}sudo systemctl status postgresql redis-server netbox netbox-rq nginx${NC}"
    echo ""
    echo -e "  ${CYAN}4.${NC} Check NetBox version:"
    echo -e "     ${YELLOW}/opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py version${NC}"
    echo ""
    echo -e "  ${CYAN}5.${NC} Save deployment information securely"
    echo ""
    log_warning "Important: Store Vault credentials and NetBox admin password securely!"
    echo ""

    return 0
}

    local iac_tool
    iac_tool=$(get_iac_tool)
    cd "${TERRAFORM_DIR}" || return
    local ssh_cmd
    ssh_cmd=$(${iac_tool} output -raw ssh_command 2>/dev/null || echo "ssh ansible@<container-ip>")
    echo -e "     ${YELLOW}${ssh_cmd} sudo cat /root/vault-keys.txt${NC}"
    echo ""

    echo -e "  ${CYAN}2.${NC} Save unseal keys and root token securely"
    echo -e "     ${YELLOW}Store in a password manager (1Password, Bitwarden, etc.)${NC}"
    echo ""

    echo -e "  ${CYAN}3.${NC} Access Vault:"
    local vault_url
    vault_url=$(${iac_tool} output -raw vault_url 2>/dev/null || echo "http://<container-ip>:8200")
    echo -e "     ${YELLOW}Web UI: ${vault_url}${NC}"
    echo ""

    echo -e "  ${CYAN}4.${NC} Security Recommendations:"
    echo -e "     ${YELLOW}- Delete /root/vault-keys.txt from container after backing up${NC}"
    echo -e "     ${YELLOW}- Configure TLS/reverse proxy for production use${NC}"
    echo -e "     ${YELLOW}- Enable audit logging${NC}"
    echo -e "     ${YELLOW}- Configure additional auth methods${NC}"
    echo ""

    log_info "Log file: ${LOG_FILE}"
    echo ""
}

# -----------------------------------------------------------------------------
# Interactive Menu
# -----------------------------------------------------------------------------

show_menu() {
    clear
    echo -e "${BOLD}${CYAN}"
    cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║     HashiCorp Vault LXC Container Deployment Script            ║
║                                                                ║
║     Automated deployment on Proxmox using                      ║
║     OpenTofu/Terraform + Ansible                               ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo -e "${BOLD}Main Menu:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Deploy Infrastructure (Full deployment)"
    echo -e "  ${BLUE}2)${NC} Dry-Run / Plan (Preview changes without applying)"
    echo -e "  ${YELLOW}3)${NC} Check Status (View current deployment status)"
    echo -e "  ${RED}4)${NC} Destroy Infrastructure (Remove all resources)"
    echo ""
    echo -e "  ${CYAN}5)${NC} Run Pre-flight Checks Only"
    echo -e "  ${CYAN}6)${NC} Run Terraform Only"
    echo -e "  ${CYAN}7)${NC} Run Ansible Only"
    echo ""
    echo -e "  ${BOLD}0)${NC} Exit"
    echo ""
}

run_preflight_checks_only() {
    log_header "Running Pre-flight Checks"

    check_binaries
    check_directories
    check_terraform_files
    check_s3_backend
    check_ssh_keys
    check_encryption_passphrase
    check_gitignore
    check_ansible_inventory
    check_environment_variables

    log_success "Pre-flight checks completed"

    echo ""
    read -p "Press Enter to continue..."
}

run_terraform_only() {
    log_header "Running Terraform Only"

    if ! check_binaries; then
        return 1
    fi

    if ! check_terraform_files; then
        return 1
    fi

    check_environment_variables

    terraform_init && terraform_validate && terraform_apply

    echo ""
    read -p "Press Enter to continue..."
}

run_ansible_only() {
    log_header "Running Ansible Only"

    if ! check_binaries; then
        return 1
    fi

    check_ansible_inventory

    ansible_test && ansible_deploy

    echo ""
    read -p "Press Enter to continue..."
}

interactive_menu() {
    while true; do
        show_menu

        echo -n "Select an option: "
        read -r choice
        echo ""

        case ${choice} in
            1)
                deploy_infrastructure
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                dry_run_deployment
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                check_deployment_status
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                destroy_infrastructure
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                run_preflight_checks_only
                ;;
            6)
                run_terraform_only
                ;;
            7)
                run_ansible_only
                ;;
            0)
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid option: ${choice}"
                sleep 2
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

main() {
    # Create logs directory
    create_logs_dir

    # Log script start
    log_info "Script started at $(date)"
    log_info "Log file: ${LOG_FILE}"

    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        # No arguments - show interactive menu
        interactive_menu
    else
        # Command line mode
        case "$1" in
            deploy)
                deploy_infrastructure
                ;;
            destroy)
                destroy_infrastructure
                ;;
            plan)
                dry_run_deployment
                ;;
            status)
                check_deployment_status
                ;;
            checks)
                run_preflight_checks_only
                ;;
            terraform)
                run_terraform_only
                ;;
            ansible)
                run_ansible_only
                ;;
            help|--help|-h)
                echo "Usage: $0 [command]"
                echo ""
                echo "Commands:"
                echo "  deploy      - Deploy full infrastructure (Terraform + Ansible)"
                echo "  destroy     - Destroy all infrastructure"
                echo "  plan        - Dry-run (plan only, no changes)"
                echo "  status      - Check deployment status"
                echo "  checks      - Run pre-flight checks only"
                echo "  terraform   - Run Terraform workflow only"
                echo "  ansible     - Run Ansible workflow only"
                echo "  help        - Show this help message"
                echo ""
                echo "No arguments: Launch interactive menu"
                ;;
            *)
                log_error "Unknown command: $1"
                log_info "Run '$0 help' for usage information"
                exit 1
                ;;
        esac
    fi

    log_info "Script completed at $(date)"
}

# Run main function
main "$@"

