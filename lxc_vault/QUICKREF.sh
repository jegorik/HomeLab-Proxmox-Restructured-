#!/usr/bin/env bash
# Quick reference for deploy.sh usage

cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║         HashiCorp Vault LXC - Deployment Quick Reference       ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

PROJECT STRUCTURE
───────────────────────────────────────────────────────────────
lxc_vault/
├── deploy.sh           # Main deployment script (~230 lines)
├── scripts/            # Modular script components
│   ├── common.sh       #   Logging, colors, utilities
│   ├── credentials.sh  #   Local file credentials (PVE password, AWS)
│   ├── terraform.sh    #   Terraform/OpenTofu operations
│   └── ansible.sh      #   Ansible inventory & deployment
├── terraform/          # Infrastructure as Code
├── ansible/            # Configuration management
│   └── roles/          # vault, tls, systemd
└── logs/               # Deployment logs

BASIC USAGE
───────────────────────────────────────────────────────────────
  ./deploy.sh              # Interactive menu (recommended)
  ./deploy.sh deploy       # Full deployment (Terraform + Ansible)
  ./deploy.sh plan         # Dry-run (preview changes)
  ./deploy.sh status       # Check deployment status
  ./deploy.sh destroy      # Destroy infrastructure
  ./deploy.sh ansible      # Ansible only
  ./deploy.sh help         # Show help

INTERACTIVE MENU OPTIONS
───────────────────────────────────────────────────────────────
  1) Deploy Infrastructure (full)
  2) Dry-Run / Plan
  3) Check Status
  4) Destroy Infrastructure
  5) Ansible Only
  0) Exit

PREREQUISITES
───────────────────────────────────────────────────────────────
Required binaries: tofu/terraform, ansible, jq, ssh

CREDENTIAL SOURCES (Priority Order)
───────────────────────────────────────────────────────────────
1. Environment variables (TF_VAR_pve_root_password)
2. File-based (~/.ssh/pve_root_password)
3. Interactive prompts

QUICK SETUP
───────────────────────────────────────────────────────────────
1. Create password file:
   echo "your-password" > ~/.ssh/pve_root_password
   chmod 600 ~/.ssh/pve_root_password

2. Configure Terraform:
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars

3. Configure S3 backend (optional):
   cp s3.backend.config.template s3.backend.config
   vim s3.backend.config

4. Generate state encryption passphrase (optional):
   openssl rand -base64 32 > ~/.ssh/state_passphrase
   chmod 600 ~/.ssh/state_passphrase

5. Deploy:
   ./deploy.sh deploy

AFTER DEPLOYMENT
───────────────────────────────────────────────────────────────
1. Get Vault keys:
   ssh ansible@<ip> sudo cat /root/vault-keys.txt

2. Access Vault UI:
   https://<container-ip>:8200

3. Secure keys:
   - Save to password manager
   - Delete from container:
     ssh ansible@<ip> sudo rm /root/vault-keys.txt

COMMON COMMANDS
───────────────────────────────────────────────────────────────
# Get container IP
cd terraform && tofu output lxc_ip_address

# SSH to container
ssh ansible@<container-ip>

# Check Vault status
ssh ansible@<ip> vault status

# View logs
tail -f logs/deployment_*.log

TROUBLESHOOTING
───────────────────────────────────────────────────────────────
Binary not found:
  ./deploy.sh plan   # Will check binaries

Terraform fails:
  cd terraform && tofu plan

Ansible connectivity fails:
  cd ansible && ansible vault -m ping -i inventory.yml

DOCUMENTATION
───────────────────────────────────────────────────────────────
Full Guide:      DEPLOYMENT.md
Main README:     README.md
Terraform:       terraform/README.md
Ansible:         ansible/README.md

EOF
