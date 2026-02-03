#!/usr/bin/env bash
# =============================================================================
# VM OpenSUSE Tumbleweed - Quick Reference Commands
# =============================================================================
# Copy-paste commands for common operations
#
# Usage: source QUICKREF.sh  (or just view for reference)
# =============================================================================

# -----------------------------------------------------------------------------
# Deployment Commands
# -----------------------------------------------------------------------------

# Full deployment (Terraform + Ansible)
# ./deploy.sh deploy

# Dry-run (plan only)
# ./deploy.sh plan

# Terraform only (create VM)
# ./deploy.sh terraform

# Ansible only (configure VM)
# ./deploy.sh ansible

# Check status
# ./deploy.sh status

# Destroy infrastructure
# ./deploy.sh destroy

# -----------------------------------------------------------------------------
# Manual Terraform Commands
# -----------------------------------------------------------------------------

# Initialize with S3 backend
# cd terraform && tofu init -backend-config=s3.backend.config

# Validate configuration
# tofu validate

# Plan changes
# tofu plan -out=tfplan

# Apply changes
# tofu apply tfplan

# Show outputs
# tofu output

# Show VM IP
# tofu output -raw vm_ip_address

# Destroy
# tofu destroy

# -----------------------------------------------------------------------------
# Manual Ansible Commands
# -----------------------------------------------------------------------------

# Inventory is at ansible/inventory.yml or ansible/inventory/inventory.yml
# (see deploy script for actual path)

# Test connectivity
# cd ansible && ansible all -m ping -i inventory.yml

# Run full playbook
# ansible-playbook -i inventory.yml site.yml

# Run specific role only
# ansible-playbook -i inventory.yml site.yml --tags common
# ansible-playbook -i inventory.yml site.yml --tags software_installation
# ansible-playbook -i inventory.yml site.yml --tags desktop_environment

# Dry-run (check mode)
# ansible-playbook -i inventory.yml site.yml --check

# Verbose output
# ansible-playbook -i inventory.yml site.yml -vvv

# -----------------------------------------------------------------------------
# VM Access Commands
# -----------------------------------------------------------------------------

# SSH to VM (replace with actual IP or use tofu output)
# ssh ansible@192.168.0.210

# SSH with specific key
# ssh -i ~/.ssh/ansible ansible@192.168.0.210

# Copy file to VM
# scp -i ~/.ssh/ansible localfile ansible@192.168.0.210:/tmp/

# -----------------------------------------------------------------------------
# Vault Commands
# -----------------------------------------------------------------------------

# Login to Vault
# vault login -method=userpass username=your-username

# Read secret
# vault kv get secret/proxmox/endpoint

# List secrets
# vault kv list secret/

# -----------------------------------------------------------------------------
# Troubleshooting Commands
# -----------------------------------------------------------------------------

# Check cloud-init status (on VM)
# cloud-init status

# View cloud-init logs (on VM)
# cat /var/log/cloud-init-output.log

# Check firewalld (on VM)
# sudo firewall-cmd --list-all

# Check disk space (on VM)
# df -h

# Check memory (on VM)
# free -h

# Check network (on VM)
# ip addr show

# -----------------------------------------------------------------------------
# Data Disk
# -----------------------------------------------------------------------------

# Data persistence disk is mounted at /data (on VM)
# ls -la /data

echo "QUICKREF.sh loaded. Commands are commented - copy and run as needed."
