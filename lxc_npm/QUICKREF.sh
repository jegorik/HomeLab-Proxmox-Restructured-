#!/usr/bin/env bash
# =============================================================================
# Nginx Proxy Manager LXC - Quick Reference Commands
# =============================================================================
# Last Updated: January 2026

echo "
╔══════════════════════════════════════════════════════════════════════════════╗
║                    NGINX PROXY MANAGER - QUICK REFERENCE                     ║
╚══════════════════════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DEPLOYMENT COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Full deployment (interactive)
./deploy.sh

# CLI commands
./deploy.sh deploy    # Full deployment
./deploy.sh plan      # Dry-run
./deploy.sh destroy   # Destroy infrastructure
./deploy.sh ansible   # Run Ansible only
./deploy.sh status    # Check status

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TERRAFORM COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

cd terraform

# Initialize with S3 backend
tofu init -backend-config=s3.backend.config

# Plan changes
tofu plan -var-file=terraform.tfvars

# Apply changes
tofu apply -var-file=terraform.tfvars

# Destroy
tofu destroy -var-file=terraform.tfvars

# View outputs
tofu output

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ANSIBLE COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

cd ansible

# Run full playbook
ansible-playbook -i inventory.yml site.yml

# Run specific role
ansible-playbook -i inventory.yml site.yml --tags npm

# Check syntax
ansible-playbook -i inventory.yml site.yml --syntax-check

# Dry run
ansible-playbook -i inventory.yml site.yml --check

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VAULT COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Login to Vault
export VAULT_ADDR='https://vault.example.com:8200'
vault login

# Read Proxmox password
vault kv get secrets/proxmox/root

# Read NetBox token
vault kv get secrets/proxmox/netbox_api_token

# Get AWS credentials (dynamic)
vault read aws/proxmox/creds/tofu_state_backup

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NPM SERVICE COMMANDS (on container)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Check service status
sudo systemctl status npm
sudo systemctl status openresty

# Restart services
sudo systemctl restart npm
sudo systemctl restart openresty

# View logs
sudo journalctl -u npm -f
sudo journalctl -u openresty -f

# Check ports
ss -tlnp | grep -E '80|81|443'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DEFAULT CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Admin UI:    http://<container-ip>:81
Email:       admin@example.com
Password:    changeme

⚠️  CHANGE DEFAULT PASSWORD IMMEDIATELY AFTER FIRST LOGIN!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PORTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Port 80   → HTTP (reverse proxy)
Port 443  → HTTPS (reverse proxy)
Port 81   → NPM Admin UI
Port 22   → SSH (management)

"
