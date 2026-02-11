# VM Docker Pool

Ubuntu Server 24.04.3 LTS VM with Docker, Docker Compose, and Portainer for container management.

## Overview

| Property | Value |
| ---------- | ------- |
| **VMID** | 300 |
| **IP Address** | 198.51.100.200/24 |
| **OS** | Ubuntu Server 24.04.3 LTS |
| **CPU** | 2 cores |
| **Memory** | 4096 MB |
| **Disk** | 32 GB |
| **Services** | Docker CE, Portainer CE |

## Features

- **Cloud-Init Deployment**: Automated VM provisioning with SSH key injection
- **Docker CE**: Latest Docker Community Edition with Compose plugin
- **Portainer CE**: Web-based Docker management on port 9443
- **Data Persistence**: Portainer data survives redeployment via bind mount
- **Security Hardening**: UFW firewall, SSH key-only auth, no root login
- **NetBox Integration**: Automatic DCIM/IPAM registration

## Quick Start

```bash
# 1. Configure variables
cd vm_docker-pool/terraform
cp terraform.tfvars.example terraform.tfvars
cp s3.backend.config.template s3.backend.config
nano terraform.tfvars  # Edit with your values

# 2. Deploy
cd ..
chmod +x deploy.sh
./deploy.sh deploy

# 3. Access Portainer
# Open https://198.51.100.200:9443
# Create admin user on first access
```

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    Proxmox VE Host                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              VM: docker-pool (VMID: 300)               │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │             Ubuntu Server 24.04.3 LTS            │  │ │
│  │  │  ┌─────────────┐  ┌───────────────────────────┐  │  │ │
│  │  │  │  Docker CE  │  │     Docker Compose        │  │  │ │
│  │  │  └─────────────┘  └───────────────────────────┘  │  │ │
│  │  │  ┌────────────────────────────────────────────┐  │  │ │
│  │  │  │           Portainer CE (:9443)             │  │  │ │
│  │  │  │  ┌──────────────────────────────────────┐  │  │  │ │
│  │  │  │  │  /opt/portainer/data (bind mount)    │  │  │  │ │
│  │  │  │  │         ↓                            │  │  │  │ │
│  │  │  └──┼──────────────────────────────────────┼──┘  │  │ │
│  │  │     │                                      │     │  │ │
│  │  └─────┼──────────────────────────────────────┼─────┘  │ │
│  │        │                                      │        │ │
│  └────────┼──────────────────────────────────────┼────────┘ │
│           │                                      │          │
│  ┌────────▼──────────────────────────────────────▼─────┐    │
│  │          /rpool/datastore/portainer                 │    │
│  │              (Persistent Storage)                   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## File Structure

```text
vm_docker-pool/
├── deploy.sh                  # Main deployment orchestrator
├── DEPLOYMENT.md             # Step-by-step deployment guide
├── QUICKREF.sh               # Quick reference commands
├── README.md                 # This file
├── ansible/
│   ├── ansible.cfg           # Ansible configuration
│   ├── inventory.yml.example # Inventory template
│   ├── site.yml              # Main playbook
│   └── roles/
│       ├── base/             # System hardening, UFW, packages
│       ├── docker/           # Docker CE installation
│       └── portainer/        # Portainer deployment
├── logs/                     # Deployment logs
├── scripts/
│   ├── ansible.sh            # Ansible helper functions
│   ├── common.sh             # Common utilities
│   ├── terraform.sh          # Terraform wrapper functions
│   └── vault.sh              # Vault authentication
└── terraform/
    ├── backend.tf            # S3 backend configuration
    ├── encryption.tf         # State file encryption configuration
    ├── main.tf               # VM resource definition
    ├── netbox.tf             # NetBox DCIM registration
    ├── outputs.tf            # Terraform outputs
    ├── providers.tf          # Provider configuration
    ├── variables.tf          # Variable definitions
    ├── terraform.tfvars.example
    └── s3.backend.config.template
```

## Vault Secrets Required

| Path | Key | Description |
| ------ | ----- | ------------- |
| `secret/proxmox/endpoint` | `url` | Proxmox API URL |
| `secret/proxmox/node` | `node_name` | Proxmox node name |
| `secret/proxmox/root` | `username`, `password` | Proxmox root credentials |
| `secret/ssh/ansible` | `public_key` | Ansible SSH public key |
| `secret/ssh/root` | `private_key` | Root SSH private key |
| `secret/netbox/api_token` | `token` | NetBox API token |
| `secret/aws/s3` | `bucket` | S3 bucket for state |

## Ports

| Port | Protocol | Service | Access |
| ------ | ---------- | --------- | -------- |
| 22 | TCP | SSH | Internal |
| 9443 | TCP | Portainer HTTPS | Internal (use NPM for external) |

## Deployment Options

| Command | Description |
| --------- | ------------- |
| `./deploy.sh` | Interactive menu |
| `./deploy.sh deploy` | Full deployment |
| `./deploy.sh plan` | Dry-run, show changes |
| `./deploy.sh terraform` | Terraform only |
| `./deploy.sh ansible` | Ansible only |
| `./deploy.sh status` | Check infrastructure status |
| `./deploy.sh destroy` | Destroy VM (preserves data) |

## Data Persistence

Portainer data is stored on the Proxmox host at `/rpool/datastore/portainer`.
This directory survives VM destruction and redeployment.

**Backup:**

```bash
# On Proxmox host
tar -czvf portainer-backup-$(date +%Y%m%d).tar.gz /rpool/datastore/portainer
```

**Restore:**

```bash
tar -xzvf portainer-backup-YYYYMMDD.tar.gz -C /
```

## Dependencies

This project depends on:

- **lxc_vault**: HashiCorp Vault for secrets management
- **lxc_netbox**: NetBox for DCIM/IPAM registration (optional)
- **lxc_npm**: Nginx Proxy Manager for SSL termination (optional)

## Troubleshooting

See [DEPLOYMENT.md](DEPLOYMENT.md#troubleshooting) for common issues and solutions.

## License

MIT License - see repository root for details.
