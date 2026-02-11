# LXC Base Template

(Golden Template: Foundation for new LXC projects)

Template for deploying standard LXC containers on Proxmox with HashiCorp Vault, NetBox integration, and S3 state storage.

## Features

- **Golden Template** – Standardized structure used by `lxc_npm`, `lxc_netbox`, etc.
- **Vault Integration** – Secrets (Proxmox password, NetBox API token) fetched from Vault (KV v2).
- **NetBox Registration** – Container auto-registered with IP, VM metadata, and resources.
- **S3 State Backend** – Remote state storage with Vault Transit encryption support.
- **Modular Architecture** – Reusable scripts in `scripts/` directory.
- **Security Hardened** – SSH key-only auth, non-root Ansible user, unprivileged container by default.

## Directory Structure

```text
lxc_base_template/
├── deploy.sh                 # Main orchestrator (Interactive Menu)
├── QUICKREF.sh               # Quick reference commands
├── README.md                 # This file
├── DEPLOYMENT.md             # Detailed deployment guide
│
├── scripts/                  # Modular scripts
│   ├── common.sh             # Logging and utilities
│   ├── vault.sh              # Vault authentication & secrets
│   ├── terraform.sh          # Terraform/OpenTofu wrappers
│   ├── ansible.sh            # Ansible inventory & execution
│   └── setup_ansible_user.sh # Ansible user bootstrapping (called by Terraform)
│
├── terraform/                # Infrastructure as Code
│   ├── main.tf               # LXC container resource
│   ├── variables.tf          # Configuration variables (lxc_*)
│   ├── encryption.tf         # State file encryption configuration  
│   ├── providers.tf          # Vault + Proxmox + NetBox providers
│   ├── netbox.tf             # NetBox registration resources
│   ├── outputs.tf            # Deployment outputs
│   ├── backend.tf            # State backend configuration
│   └── terraform.tfvars.example # Example configuration
│
└── ansible/                  # Configuration Management
    ├── site.yml              # Main playbook
    └── roles/                
        └── base/             # Base system configuration
```

## Quick Start (Creating a New Project)

1. **Clone/Copy** this template to a new directory:

   ```bash
   cp -r lxc_base_template lxc_new_project
   cd lxc_new_project
   ```

2. **Configure Variables**:

   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   vim terraform/terraform.tfvars
   ```

   *Edit `lxc_hostname`, `lxc_id` (VMID), `lxc_ip_address`, and Vault paths.*

3. **Configure S3 Backend (Optional but Recommended)**:

   ```bash
   cp terraform/s3.backend.config.template terraform/s3.backend.config
   # Edit bucket and key details
   ```

   *If skipping this, state will be stored locally in `terraform/terraform.tfstate`.*

4. **Deploy**:

   ```bash
   ./deploy.sh deploy
   ```

   *Follow the interactive prompts to authenticate with Vault.*

## Configuration Reference

### Key Variables (`terraform.tfvars`)

| Variable | Description | Default |
| ---------- | ------------- | --------- |
| `lxc_id` | Proxmox VMID | `106` |
| `lxc_hostname` | Container hostname | `base-template` |
| `lxc_ip_address` | IPv4/CIDR (e.g., `192.0.2.50/24`) | `dhcp` |
| `lxc_disk_storage` | Storage pool | `local-lvm` |
| `lxc_disk_size` | Disk size (GB) | `8` |
| `lxc_memory` | RAM (MB) | `512` |
| `lxc_cpu_cores` | CPU Cores | `1` |

### Vault Secrets

The template expects the following secrets in Vault (paths configurable in `variables.tf`):

- `secret/proxmox/root` (password)
- `secret/netbox/api` (token)
- `ssh/root_public_key`
- `ssh/root_private_key` (for Ansible connection)

## Deployment Commands

| Command | Description |
| --------- | ------------- |
| `./deploy.sh` | Open Interactive Menu |
| `./deploy.sh deploy` | Full Deployment (Vault -> Terraform -> Ansible) |
| `./deploy.sh plan` | Terraform Plan (Dry-run) |
| `./deploy.sh terraform` | Terraform Apply Only (No Ansible) |
| `./deploy.sh ansible` | Ansible Playbook Only |
| `./deploy.sh status` | Check Deployment Status |
| `./deploy.sh destroy` | Destroy Infrastructure |

## Requirements

- **Proxmox VE** 8.x
- **HashiCorp Vault** (Unsealed)
- **NetBox** (Optional, but enabled by default)
- **OpenTofu** or **Terraform** >= 1.0
- **Ansible** >= 2.15

## License

MIT
