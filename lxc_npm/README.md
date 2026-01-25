# Nginx Proxy Manager LXC Container

Automated deployment of Nginx Proxy Manager in a Proxmox LXC container with HashiCorp Vault integration, NetBox registration, and S3 state storage.

## Features

- **Nginx Proxy Manager** – Web-based reverse proxy management with SSL support
- **Vault Integration** – Secrets (Proxmox password, NetBox API token) fetched from Vault
- **NetBox Registration** – Container auto-registered with IP and VM metadata
- **S3 State Backend** – Remote state storage with Vault Transit encryption
- **Security Hardened** – SSH key-only auth, UFW firewall, no root login, **Unprivileged Container**
- **Data Persistence** – Bind mounts for `/data` and `/etc/letsencrypt` with automated permission fix

## Ports

| Port | Service | Description |
| ------ | --------- | ------------- |
| 80 | HTTP | Reverse proxy HTTP traffic |
| 443 | HTTPS | Reverse proxy HTTPS/SSL traffic |
| 81 | Admin UI | NPM management interface |

## Quick Start

```bash
# 1. Configure terraform.tfvars
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars

# 2. Configure S3 backend
cp terraform/s3.backend.config.template terraform/s3.backend.config
vim terraform/s3.backend.config

# 3. Set Vault environment (or will be prompted)
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs.xxxxx"

# 4. Deploy
./deploy.sh deploy
```

## Default Credentials

After deployment, access the admin UI at `http://<container-ip>:81`:

- **Email**: `admin@example.com`
- **Password**: `changeme`

> [!IMPORTANT]
> Change the default credentials immediately after first login!

## Directory Structure

```text
lxc_npm/
├── deploy.sh                 # Main orchestrator
├── QUICKREF.sh               # Quick reference commands
├── README.md                 # This file
├── DEPLOYMENT.md             # Step-by-step guide
│
├── scripts/
│   ├── common.sh             # Logging utilities
│   ├── vault.sh              # Vault authentication & AWS credentials
│   ├── terraform.sh          # Terraform operations
│   ├── ansible.sh            # Ansible operations
│   └── setup_ansible_user.sh # Ansible user bootstrapping
│
├── terraform/
│   ├── main.tf               # LXC container resource
│   ├── variables.tf          # Configuration variables
│   ├── providers.tf          # Vault + Proxmox + NetBox
│   ├── netbox.tf             # NetBox registration
│   ├── outputs.tf            # Deployment outputs
│   ├── backend.tf            # S3 state backend
│   └── encryption.tf         # Vault Transit encryption
│
└── ansible/
    ├── site.yml              # Main playbook
    └── roles/
        ├── base/             # Base system configuration
        └── npm/              # Nginx Proxy Manager installation
```

## Prerequisites

- OpenTofu >= 1.8 or Terraform >= 1.5
- Ansible >= 2.15
- HashiCorp Vault (running and unsealed)
- NetBox instance (for registration)
- Proxmox VE 8.x
- S3-compatible storage for state

## Vault Secrets Setup

Store secrets in Vault before deployment:

```bash
# Proxmox credentials
vault kv put secrets/proxmox/root password="your-pve-password"

# NetBox API token
vault kv put secrets/proxmox/netbox_api_token token="your-netbox-token"

# AWS credentials for S3 backend (or use dynamic credentials)
vault kv put secrets/aws/tofu access_key="..." secret_key="..."
```

## Commands

| Command | Description |
| --------- | ------------- |
| `./deploy.sh` | Interactive menu |
| `./deploy.sh deploy` | Full deployment |
| `./deploy.sh plan` | Dry-run |
| `./deploy.sh destroy` | Destroy infrastructure |
| `./deploy.sh ansible` | Run Ansible only |
| `./deploy.sh status` | Check status |

## Resource Requirements

| Resource | Minimum | Recommended |
| --------- | --------- | ------------- |
| CPU Cores | 1 | 2 |
| RAM | 1 GB | 2 GB |
| Disk | 4 GB | 8 GB |

> [!NOTE]
> NPM requires additional RAM during initial build (Node.js compilation).

## Post-Deployment

1. Access admin UI: `http://<container-ip>:81`
2. Login with default credentials
3. Change admin password immediately
4. Add proxy hosts for your services
5. Configure SSL certificates (Let's Encrypt or custom)

## License

MIT

---

**Last Updated**: January 2026
