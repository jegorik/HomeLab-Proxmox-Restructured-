# Proxmox Backup Server (LXC)

Project for deploying Proxmox Backup Server (PBS) in a Proxmox LXC container using OpenTofu/Terraform and Ansible.
Based on `lxc_base_template`.

## Features

- **Proxmox Backup Server** – Enterprise backup solution from Proxmox, installed from official repositories.
- **Data Persistence** – Bind mounts for configuration (`/etc/proxmox-backup`) and datastore (`/mnt/pbs-backups`).
- **Vault Integration** – Secrets (Proxmox credentials, SSH keys) fetched from HashiCorp Vault.
- **NetBox Registration** – Container auto-registered with IP, VM metadata, and resources.
- **S3 State Backend** – Remote state storage with Vault Transit encryption.
- **Security Hardened** – SSH key-only auth, non-root Ansible user, UFW firewall enabled.

## Directory Structure

```text
lxc_PBS/
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
│   └── setup_ansible_user.sh # Ansible user bootstrapping
│
├── terraform/                # Infrastructure as Code
│   ├── main.tf               # LXC container resource with bind mounts
│   ├── encryption.tf         # State file encryption configuration
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
        └── pbs/              # PBS installation and configuration
```

## Configuration Reference

### Key Variables (`terraform.tfvars`)

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `lxc_id` | Proxmox VMID | `107` |
| `lxc_hostname` | Container hostname | `pbs` |
| `lxc_ip_address` | IPv4/CIDR | `dhcp` |
| `lxc_disk_storage` | Storage pool | `local-lvm` |
| `lxc_disk_size` | Disk size (GB) | `18` |
| `lxc_memory` | RAM (MB) | `4096` |
| `lxc_cpu_cores` | CPU Cores | `4` |
| `lxc_unprivileged` | Unprivileged container | `true` (security recommended) |

### PBS-Specific Bind Mounts

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `lxc_pbs_config_mount_volume` | Host path for PBS config | `/rpool/data/pbs-config` |
| `lxc_pbs_config_mount_path` | Container path for config | `/etc/proxmox-backup` |
| `lxc_pbs_datastore_mount_volume` | Host path for backups | `/rpool/data/pbs-backups` |
| `lxc_pbs_datastore_mount_path` | Container path for backups | `/mnt/datastore` |

> [!IMPORTANT]
> **Unprivileged Container UID Mapping**
>
> PBS runs in unprivileged mode with the `backup` user (UID 34 inside container, mapped to UID 100034 on host).
>
> **Host-side bind mount permissions must be set correctly:**
>
> ```bash
> chown -R 100034:100034 /rpool/data/pbs-config
> chown -R 100034:100034 /rpool/data/pbs-backups
> ```
>
> See the main [README.md](../README.md#unprivileged-containers--uid-mapping) for more details on UID mapping.

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

3. **Ensure Host Paths Exist** (on Proxmox host):

   ```bash
   mkdir -p /rpool/data/pbs-config
   mkdir -p /rpool/data/pbs-backups
   ```

4. **Deploy**:

   ```bash
   ./deploy.sh deploy
   ```

5. **Access PBS**:
   - Web UI: `https://<IP>:8007`
   - SSH: `ssh ansible@<IP>`

## Requirements

- **Proxmox VE** 8.x
- **HashiCorp Vault** (Unsealed)
- **NetBox** (Optional, but enabled by default)
- **OpenTofu** or **Terraform** >= 1.0
- **Ansible** >= 2.15

## Ports

| Port | Protocol | Description |
| ---- | -------- | ----------- |
| 22 | TCP | SSH |
| 8007 | TCP | PBS Web UI |

## License

MIT
