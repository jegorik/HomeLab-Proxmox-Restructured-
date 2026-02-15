#!/usr/bin/env bash
# =============================================================================
# LXC PBS- Quick Reference
# =============================================================================
# Common commands and operations for quick access
# Run with: source ./QUICKREF.sh or just view for reference

# -----------------------------------------------------------------------------
# Deployment Commands
# -----------------------------------------------------------------------------

# Full deployment (interactive)
alias lxc-deploy="./deploy.sh"

# Full deployment (non-interactive)
alias lxc-deploy-full="./deploy.sh deploy"

# Plan only (dry-run)
alias lxc-plan="./deploy.sh plan"

# Destroy infrastructure
alias lxc-destroy="./deploy.sh destroy"

# Check status
alias lxc-status="./deploy.sh status"

# -----------------------------------------------------------------------------
# Terraform Commands
# -----------------------------------------------------------------------------

# Initialize Terraform
tf-init() {
    cd terraform && tofu init && cd ..
}

# Validate configuration
tf-validate() {
    cd terraform && tofu validate && cd ..
}

# Show plan
tf-plan() {
    cd terraform && tofu plan && cd ..
}

# Apply changes
tf-apply() {
    cd terraform && tofu apply && cd ..
}

# Show outputs
tf-output() {
    cd terraform && tofu output && cd ..
}

# -----------------------------------------------------------------------------
# Ansible Commands
# -----------------------------------------------------------------------------

# Test connectivity
ansible-ping() {
    cd ansible && ansible all -m ping -i inventory.yml && cd ..
}

# Run playbook
ansible-run() {
    cd ansible && ansible-playbook -i inventory.yml site.yml && cd ..
}

# Run playbook with verbose
ansible-run-v() {
    cd ansible && ansible-playbook -i inventory.yml site.yml -vvv && cd ..
}

# -----------------------------------------------------------------------------
# Vault Commands (requires vault CLI)
# -----------------------------------------------------------------------------

# Check Vault status
vault-status() {
    vault status
}

# Read Proxmox secret
vault-read-pve() {
    vault kv get secret/proxmox/root
}

# Read NetBox secret
vault-read-netbox() {
    vault kv get secret/netbox/api
}

# -----------------------------------------------------------------------------
# Quick Setup
# -----------------------------------------------------------------------------

echo "LXC PBS Quick Reference loaded!"
echo ""
echo "Commands:"
echo "  lxc-deploy       - Interactive deployment menu"
echo "  lxc-deploy-full  - Full non-interactive deployment"
echo "  lxc-plan         - Dry-run / plan only"
echo "  lxc-status       - Check deployment status"
echo "  lxc-destroy      - Destroy infrastructure"
echo ""
echo "Terraform: tf-init, tf-validate, tf-plan, tf-apply, tf-output"
echo "Ansible:   ansible-ping, ansible-run, ansible-run-v"
echo "Vault:     vault-status, vault-read-pve, vault-read-netbox"
echo ""
