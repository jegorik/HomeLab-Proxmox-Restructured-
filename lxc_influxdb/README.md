# InfluxDB LXC Container Deployment

[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.8+-844fba.svg)](https://opentofu.org/)
[![Ansible](https://img.shields.io/badge/Ansible-2.15+-EE0000.svg)](https://www.ansible.com/)
[![Proxmox](https://img.shields.io/badge/Proxmox-8.x-E57000.svg)](https://www.proxmox.com/)
[![Vault](https://img.shields.io/badge/HashiCorp_Vault-Required-844fba.svg)](https://www.vaultproject.io/)

Project for deploying InfluxDB 2.x time-series database in a Proxmox LXC container using OpenTofu/Terraform and Ansible. Based on `lxc_base_template`.

## Features

- **InfluxDB 2.x** – Modern time-series database with built-in UI, Flux query language, and HTTP API.
- **Data Persistence** – Bind mount for InfluxDB data directory (`/var/lib/influxdb`).
- **Initial Setup** – Automated admin user, organization, and bucket creation.
- **Vault Integration** – Secrets (Proxmox credentials, SSH keys) fetched from HashiCorp Vault.
- **NetBox Registration** – Container auto-registered with IP, VM metadata, and resources.
- **S3 State Backend** – Remote state storage with Vault Transit encryption.
- **Security Hardened** – SSH key-only auth, non-root Ansible user, UFW firewall enabled.

## Directory Structure

```text
lxc_influxdb/
├── deploy.sh                 # Main orchestrator (Interactive Menu)
├── QUICKREF.sh               # Quick reference commands
├── README.md                 # This file
├── DEPLOYMENT.md             # Detailed deployment guide
│
├── scripts/                  # Modular scripts
│   ├── common.sh             # Logging and utilities
│   ├── vault.sh              # Vault authentication & secrets
│   ├── terraform.sh          # Terraform/OpenTofu wrappers
│   └── ansible.sh            # Ansible inventory & execution
│
├── terraform/                # Infrastructure as Code
│   ├── main.tf               # LXC container resource with bind mounts
│   ├── variables.tf          # Configuration variables
│   ├── providers.tf          # Vault + Proxmox + NetBox providers
│   ├── netbox.tf             # NetBox registration resources
│   ├── outputs.tf            # Deployment outputs
│   ├── backend.tf            # State backend configuration
│   └── terraform.tfvars.example # Example configuration
│
└── ansible/                  # Configuration Management
    ├── site.yml              # Main playbook
    └── roles/
        ├── base/             # Base system configuration (SSH, UFW)
        └── influxdb/         # InfluxDB installation and setup
```

## Configuration Reference

### Key Variables (`terraform.tfvars`)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `lxc_id` | Proxmox VMID | `102` |
| `lxc_hostname` | Container hostname | `influxdb` |
| `lxc_ip_address` | IPv4/CIDR | `dhcp` |
| `lxc_disk_storage` | Storage pool | `local-zfs` |
| `lxc_disk_size` | Disk size (GB) | `8` |
| `lxc_memory` | RAM (MB) | `512` |
| `lxc_cpu_cores` | CPU Cores | `2` |
| `lxc_unprivileged` | Unprivileged container | `false` (required for bind mounts) |

### InfluxDB Data Persistence (Bind Mount)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `lxc_influxdb_data_mount_volume` | Host path for InfluxDB data | `/rpool/datastore/influxdb` |
| `lxc_influxdb_data_mount_path` | Container path | `/var/lib/influxdb` |

### InfluxDB Setup Variables (Ansible)

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `influxdb_admin_user` | `admin` | Initial admin username |
| `influxdb_admin_password` | `changeme123!` | Initial admin password |
| `influxdb_org` | `homelab` | Initial organization |
| `influxdb_bucket` | `default` | Initial bucket |
| `influxdb_retention` | `0` | Retention (0 = infinite) |

### Vault Secrets

The project expects the following secrets in Vault (paths configurable in `variables.tf`):

- `secret/proxmox/root` (password)
- `secret/netbox/api` (token)
- `ssh/root_public_key`
- `ssh/root_private_key` (for Ansible connection)
- `ssh/ansible_public_key`

## Deployment Commands

| Command | Description |
| ------- | ----------- |
| `./deploy.sh` | Open Interactive Menu |
| `./deploy.sh deploy` | Full Deployment (Vault → Terraform → Ansible) |
| `./deploy.sh plan` | Terraform Plan (Dry-run) |
| `./deploy.sh terraform` | Terraform Apply Only (No Ansible) |
| `./deploy.sh ansible` | Ansible Playbook Only |
| `./deploy.sh status` | Check Deployment Status |
| `./deploy.sh destroy` | Destroy Infrastructure |

## Usage

1. **Configure Variables**:

   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   vim terraform/terraform.tfvars
   ```

2. **Configure S3 Backend (Recommended)**:

   ```bash
   cp terraform/s3.backend.config.template terraform/s3.backend.config
   vim terraform/s3.backend.config
   ```

3. **Ensure Host Path Exists** (on Proxmox host):

   ```bash
   mkdir -p /rpool/datastore/influxdb
   ```

4. **Deploy**:

   ```bash
   ./deploy.sh deploy
   ```

5. **Access InfluxDB**:
   - Web UI: `http://<IP>:8086`
   - SSH: `ssh ansible@<IP>`

## Requirements

- **Proxmox VE** 8.x
- **HashiCorp Vault** (Unsealed)
- **NetBox** (Optional, but enabled by default)
- **OpenTofu** or **Terraform** >= 1.0
- **Ansible** >= 2.15

> [!IMPORTANT]
> InfluxDB bind mounts require a **privileged container** (`lxc_unprivileged = false`).

## Ports

| Port | Protocol | Description |
| ---- | -------- | ----------- |
| 22 | TCP | SSH |
| 8086 | TCP | InfluxDB HTTP API / UI |

## License

MIT
