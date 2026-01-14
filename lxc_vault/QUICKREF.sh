#!/usr/bin/env bash
# Quick reference for deploy.sh usage

cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║         HashiCorp Vault LXC - Deployment Quick Reference       ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

BASIC USAGE
───────────────────────────────────────────────────────────────
  ./deploy.sh              # Interactive menu
  ./deploy.sh deploy       # Full deployment (Terraform + Ansible)
  ./deploy.sh plan         # Dry-run (preview changes)
  ./deploy.sh status       # Check deployment status
  ./deploy.sh destroy      # Destroy infrastructure
  ./deploy.sh help         # Show help

ADVANCED USAGE
───────────────────────────────────────────────────────────────
  ./deploy.sh checks       # Pre-flight checks only
  ./deploy.sh terraform    # Terraform workflow only
  ./deploy.sh ansible      # Ansible workflow only

ENVIRONMENT VARIABLES
───────────────────────────────────────────────────────────────
Required:
  TF_VAR_pve_root_password    # Proxmox root@pam password
  OR file: ~/.ssh/pve_root_password

Optional (can be in terraform.tfvars):
  TF_VAR_proxmox_endpoint     # https://proxmox-ip:8006
  TF_VAR_proxmox_node         # pve
  TF_VAR_lxc_ip_address       # 10.0.100.50/24
  TF_VAR_lxc_gateway          # 10.0.100.1

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

4. Generate state encryption passphrase:
   openssl rand -base64 32 > ~/.ssh/state_passphrase
   chmod 600 ~/.ssh/state_passphrase

5. Deploy:
   ./deploy.sh deploy

LOGS
───────────────────────────────────────────────────────────────
Location: logs/deployment_YYYYMMDD_HHMMSS.log

View:      tail -f logs/deployment_*.log
Search:    grep ERROR logs/*.log
Filter:    grep -E "ERROR|WARNING" logs/*.log

TROUBLESHOOTING
───────────────────────────────────────────────────────────────
Binary not found:
  ./deploy.sh checks

Terraform fails:
  cd terraform && tofu plan

Ansible connectivity fails:
  cd ansible && ansible vault -m ping

Re-run specific component:
  ./deploy.sh terraform    # or
  ./deploy.sh ansible

AFTER DEPLOYMENT
───────────────────────────────────────────────────────────────
1. Get Vault keys:
   ssh ansible@<ip> sudo cat /root/vault-keys.txt

2. Access Vault UI:
   # URL from: ./deploy.sh status

3. Secure keys:
   - Save to password manager
   - Delete from container
   - ssh ansible@<ip> sudo rm /root/vault-keys.txt

CREDENTIAL PRIORITY
───────────────────────────────────────────────────────────────
1. Environment variables (TF_VAR_*)     [Highest]
2. File-based (~/.ssh/pve_root_password)
3. Interactive prompts
4. terraform.tfvars                     [Lowest]

PRE-REQUISITES CHECK
───────────────────────────────────────────────────────────────
Required Software:
  ✓ OpenTofu/Terraform
  ✓ Ansible
  ✓ SSH client
  ✓ Git
  ✓ jq
  ✓ AWS CLI (optional for S3 backend)

Required Files:
  ✓ terraform/terraform.tfvars
  ✓ ~/.ssh/pve_ssh (SSH keys)
  ✓ ~/.ssh/ansible (SSH keys)
  ✓ ~/.ssh/state_passphrase (optional)

Proxmox:
  ✓ LXC template downloaded
  ✓ Network bridge (vmbr0)
  ✓ Root@pam credentials

DOCUMENTATION
───────────────────────────────────────────────────────────────
Full Guide:      DEPLOYMENT.md
Main README:     README.md
Terraform:       terraform/README.md
Ansible:         ansible/README.md

SAFETY FEATURES
───────────────────────────────────────────────────────────────
✓ Pre-flight validation
✓ Dry-run mode available
✓ Confirmation prompts for destructive actions
✓ Double confirmation for destroy
✓ Comprehensive logging
✓ Error recovery instructions

EOF

