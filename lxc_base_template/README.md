# LXC Base Template

Template for deploying LXC containers on Proxmox with HashiCorp Vault and NetBox integration.

## Features

- **Vault Integration** – Secrets (Proxmox password, NetBox API token) fetched from Vault
- **NetBox Registration** – Container auto-registered with IP and VM metadata
- **Modular Architecture** – Reusable scripts and Ansible roles
- **Security Hardened** – SSH key-only auth, UFW firewall, no root login

## Quick Start

```bash
# 1. Configure terraform.tfvars
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars

# 2. Set Vault environment (or will be prompted)
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs.xxxxx"

# 3. Deploy
./deploy.sh deploy
```

## Directory Structure

```
lxc_base_template/
├── deploy.sh                 # Main orchestrator
├── QUICKREF.sh               # Quick reference commands
├── README.md                 # This file
├── DEPLOYMENT.md             # Step-by-step guide
│
├── scripts/
│   ├── common.sh             # Logging utilities
│   ├── credentials.sh        # Vault secret loading
│   ├── terraform.sh          # Terraform operations
│   └── ansible.sh            # Ansible operations
│
├── terraform/
│   ├── main.tf               # LXC container resource
│   ├── variables.tf          # Configuration variables
│   ├── providers.tf          # Vault + Proxmox + NetBox
│   ├── netbox.tf             # NetBox registration
│   ├── outputs.tf            # Deployment outputs
│   └── backend.tf            # State backend
│
└── ansible/
    ├── site.yml              # Main playbook
    └── roles/base/           # Base configuration role
```

## Prerequisites

- OpenTofu or Terraform >= 1.0
- Ansible >= 2.10
- HashiCorp Vault (running and unsealed)
- NetBox instance
- Proxmox VE

## Vault Secrets Setup

Store secrets in Vault before deployment:

```bash
# Proxmox credentials
vault kv put secret/proxmox/root password="your-pve-password"

# NetBox API token
vault kv put secret/netbox/api api_token="your-netbox-token"
```

## Commands

| Command | Description |
|---------|-------------|
| `./deploy.sh` | Interactive menu |
| `./deploy.sh deploy` | Full deployment |
| `./deploy.sh plan` | Dry-run |
| `./deploy.sh destroy` | Destroy infrastructure |
| `./deploy.sh ansible` | Run Ansible only |
| `./deploy.sh status` | Check status |

## Creating New Containers

1. Copy this template to a new directory
2. Customize `terraform.tfvars`
3. Add application-specific Ansible roles
4. Run `./deploy.sh deploy`

## License

MIT
