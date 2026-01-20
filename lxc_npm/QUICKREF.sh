#!/usr/bin/env bash
# Quick reference for deploy.sh usage

cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║      Nginx Proxy Manager LXC - Deployment Quick Reference      ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

PROJECT STRUCTURE
───────────────────────────────────────────────────────────────
lxc_npm/
├── deploy.sh           # Main deployment script
├── scripts/            # Modular script components
│   ├── common.sh       #   Logging, colors, utilities
│   ├── vault.sh        #   Vault authentication & AWS credentials
│   ├── terraform.sh    #   Terraform/OpenTofu operations
│   └── ansible.sh      #   Ansible inventory & deployment
├── terraform/          # Infrastructure as Code
├── ansible/            # Configuration management
│   └── roles/          # base, npm
└── logs/               # Deployment logs

BASIC USAGE
───────────────────────────────────────────────────────────────
  ./deploy.sh              # Interactive menu (recommended)
  ./deploy.sh deploy       # Full deployment (Vault + Terraform + Ansible)
  ./deploy.sh plan         # Dry-run (preview changes)
  ./deploy.sh status       # Check deployment status
  ./deploy.sh destroy      # Destroy infrastructure
  ./deploy.sh ansible      # Ansible only (requires VAULT_TOKEN)
  ./deploy.sh terraform    # Terraform only (no Ansible)
  ./deploy.sh help         # Show help

INTERACTIVE MENU OPTIONS
───────────────────────────────────────────────────────────────
  1) Deploy Infrastructure (full)
  2) Dry-Run / Plan
  3) Check Status
  4) Destroy Infrastructure
  5) Ansible Only (requires VAULT_TOKEN)
  6) Terraform Only (no Ansible)
  0) Exit

PREREQUISITES
───────────────────────────────────────────────────────────────
⚠️  HashiCorp Vault REQUIRED (deploy lxc_vault first)
    See: ../lxc_vault/README.md

Required binaries: tofu/terraform, ansible, vault, jq, ssh

VAULT AUTHENTICATION
───────────────────────────────────────────────────────────────
The deploy.sh script handles Vault authentication automatically:
  • Prompts for VAULT_ADDR if not set
  • Prompts for VAULT_USERNAME if not set
  • Prompts for password during authentication
  • Token stored in VAULT_TOKEN environment variable
  • No credential caching (simplified security model)

Set Environment Variables (Optional):
  export VAULT_ADDR='https://vault.example.com:8200'
  export VAULT_USERNAME='your_username'

STANDALONE ANSIBLE EXECUTION
───────────────────────────────────────────────────────────────
To run Ansible independently (e.g., re-run configuration):

  # Set VAULT_TOKEN before running
  export VAULT_TOKEN=$(vault print token)
  ./deploy.sh ansible

  # Or run Ansible manually
  export VAULT_TOKEN=$(vault print token)
  cd ansible
  ansible-playbook -i inventory.yml site.yml

Note: VAULT_TOKEN is passed via environment variable (secure, not shown in logs)

BIND MOUNTS (DATA PERSISTENCE)
───────────────────────────────────────────────────────────────
Default mount points (configurable in terraform.tfvars):
  Host: /mnt/pve/.../lxc_npm/data → Container: /data

User data preserved across container recreation:
  • Database (database.sqlite)
  • SSL certificates
  • Proxy host configurations

NPM SERVICES
───────────────────────────────────────────────────────────────
Check all services (inside container):
  ssh ansible@<container-ip>
  sudo systemctl status npm openresty

View logs:
  sudo journalctl -u npm -f
  sudo journalctl -u openresty -f

NPM PORTS
───────────────────────────────────────────────────────────────
  Port 80   - HTTP proxy traffic
  Port 443  - HTTPS proxy traffic
  Port 81   - Admin UI

QUICK SETUP
───────────────────────────────────────────────────────────────
1. (Optional) Set Vault environment variables:
   export VAULT_ADDR='https://vault.example.com:8200'
   export VAULT_USERNAME='your_username'
   # Or let script prompt you during deployment

2. Configure Terraform:
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars

3. Configure S3 backend:
   cp s3.backend.config.template s3.backend.config
   vim s3.backend.config

4. Run deployment:
   cd ..
   ./deploy.sh deploy
   # Script will prompt for Vault configuration if not set

5. Ansible inventory is auto-generated from Terraform outputs

ACCESSING NPM
───────────────────────────────────────────────────────────────
Web Interface:
  http://<container-ip>:81

Default Credentials:
  Email:    admin@example.com
  Password: changeme

⚠️  CHANGE DEFAULT PASSWORD IMMEDIATELY!

COMMON COMMANDS
───────────────────────────────────────────────────────────────
# Get container IP
cd terraform && tofu output lxc_ip_address

# SSH to container
ssh ansible@<container-ip>

# Restart NPM services
sudo systemctl restart npm openresty

# Check NPM database
ls -la /data/database.sqlite

VAULT SECRETS PATHS
───────────────────────────────────────────────────────────────
Required in Vault KV (must be created before deployment):
  secrets/proxmox/credentials   # endpoint, node, password
  secrets/proxmox/ssh_keys      # root_public, root_private, ansible_public
  secrets/proxmox/netbox_api_token  # NetBox API token

Vault Transit Engine:
  transit/keys/tofu-state-encryption

AWS Dynamic Credentials:
  aws/proxmox/creds/tofu_state_backup

TROUBLESHOOTING
───────────────────────────────────────────────────────────────
# Test Vault connectivity
vault status

# Verify Vault secrets exist
vault kv list secrets/proxmox

# Check Transit key
vault read transit/keys/tofu-state-encryption

# NPM not starting? Check logs
ssh ansible@<container-ip>
sudo journalctl -u npm -n 50

# Port 81 not responding?
sudo systemctl status npm openresty
sudo ss -tlnp | grep -E ':(81|3000)'

# View deployment logs
tail -f logs/deployment_*.log

LINKS
───────────────────────────────────────────────────────────────
Documentation:  README.md
Deployment:     DEPLOYMENT.md
Vault Setup:    ../lxc_vault/README.md
NPM Docs:       https://nginxproxymanager.com/

EOF
