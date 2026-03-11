#!/usr/bin/env bash
# =============================================================================
# VM Docker Pool - Quick Reference Commands
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

# Show specific output
# tofu output -raw vm_password

# Destroy
# tofu destroy

# -----------------------------------------------------------------------------
# Manual Ansible Commands
# -----------------------------------------------------------------------------

# Test connectivity
# cd ansible && ansible all -m ping -i inventory.yml

# Run full playbook
# ansible-playbook -i inventory.yml site.yml

# Run specific role only
# ansible-playbook -i inventory.yml site.yml --tags base
# ansible-playbook -i inventory.yml site.yml --tags docker
# ansible-playbook -i inventory.yml site.yml --tags portainer

# Dry-run (check mode)
# ansible-playbook -i inventory.yml site.yml --check

# Verbose output
# ansible-playbook -i inventory.yml site.yml -vvv

# -----------------------------------------------------------------------------
# VM Access Commands
# -----------------------------------------------------------------------------

# SSH to VM
# ssh ansible@198.51.100.200

# SSH with specific key
# ssh -i ~/.ssh/ansible ansible@198.51.100.200

# Copy file to VM
# scp -i ~/.ssh/ansible localfile ansible@198.51.100.200:/tmp/

# -----------------------------------------------------------------------------
# Docker Commands (on VM)
# -----------------------------------------------------------------------------

# List running containers
# docker ps

# List all containers
# docker ps -a

# View container logs
# docker logs portainer

# Follow container logs
# docker logs -f portainer

# Enter container shell
# docker exec -it portainer /bin/sh

# Restart Portainer
# cd /opt/portainer && docker compose restart

# Update Portainer
# cd /opt/portainer && docker compose pull && docker compose up -d

# Docker system info
# docker system info

# Clean up unused resources
# docker system prune -af

# -----------------------------------------------------------------------------
# Portainer URLs
# -----------------------------------------------------------------------------

# Portainer Web UI (HTTPS)
# https://198.51.100.200:9443

# Portainer API
# https://198.51.100.200:9443/api

# -----------------------------------------------------------------------------
# Vault Commands
# -----------------------------------------------------------------------------

# Login to Vault
# vault login -method=userpass username=your-username

# Read secret
# vault kv get secret/docker-pool/config

# Write secret
# vault kv put secret/docker-pool/config key=value

# List secrets
# vault kv list secret/docker-pool/

# -----------------------------------------------------------------------------
# Troubleshooting Commands
# -----------------------------------------------------------------------------

# Check cloud-init status (on VM)
# cloud-init status

# View cloud-init logs (on VM)
# cat /var/log/cloud-init-output.log

# Check Docker status (on VM)
# systemctl status docker

# Check Portainer status (on VM)
# docker ps | grep portainer

# Check UFW status (on VM)
# sudo ufw status verbose

# Check disk space (on VM)
# df -h

# Check memory (on VM)
# free -h

# Check network (on VM)
# ip addr show

# -----------------------------------------------------------------------------
# Backup Commands
# -----------------------------------------------------------------------------

# Backup Portainer data (on Proxmox host)
# tar -czvf portainer-backup-$(date +%Y%m%d).tar.gz /rpool/datastore/portainer

# Restore Portainer data (on Proxmox host)
# tar -xzvf portainer-backup-YYYYMMDD.tar.gz -C /

echo "QUICKREF.sh loaded. Commands are commented - copy and run as needed."
