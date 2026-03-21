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
- **Data Persistence**: All Docker volumes survive redeployment via NFS to PVE host
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
┌────────────────────────────────────────────────────────────┐
│                    Proxmox VE Host                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │   /rpool/datastore/docker-pool/volumes (ZFS + PBS)   │  │
│  │              NFS Export ────────────────┐            │  │
│  └─────────────────────────────────────────┤────────────┘  │
│                                            │               │
│  ┌─────────────────────────────────────────▼────────────┐  │
│  │              VM: docker-pool (VMID: 300)             │  │
│  │  ┌──────────────────────────────────────────────┐    │  │
│  │  │             Ubuntu Server 24.04.3 LTS        │    │  │
│  │  │  ┌─────────────┐  ┌───────────────────────┐  │    │  │
│  │  │  │  Docker CE  │  │   Docker Compose      │  │    │  │
│  │  │  └─────────────┘  └───────────────────────┘  │    │  │
│  │  │  ┌────────────────────────────────────────┐  │    │  │
│  │  │  │        Portainer CE (:9443)            │  │    │  │
│  │  │  │        + Any deployed stacks           │  │    │  │
│  │  │  └────────────────────────────────────────┘  │    │  │
│  │  │        │                                     │    │  │
│  │  │        ▼ Docker Named Volumes                │    │  │
│  │  │  /var/lib/docker/volumes ◄── NFS mount ──────┘    │  │
│  │  └──────────────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
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

All Docker named volumes are stored on the Proxmox host via NFS at
`/rpool/datastore/docker-pool/volumes`. This includes Portainer data and any
container stacks deployed through Portainer or Docker Compose.

This directory:

- Survives VM destruction and redeployment
- Lives on ZFS with snapshots and compression
- Is covered by PBS (Proxmox Backup Server) automatically

**How it works:**

1. Terraform creates the NFS export on the PVE host
2. Ansible mounts the NFS export at `/var/lib/docker/volumes` in the VM
3. Docker's systemd unit depends on the NFS mount (won't start without it)
4. Every Docker named volume automatically resides on PVE storage

> **NFS Considerations:** Mounting NFS at `/var/lib/docker/volumes` places
> Docker's internal volume metadata (`metadata.db`, a BoltDB file) on a remote
> filesystem. This is acceptable with NFSv4 on a reliable LAN (proper file
> locking, single-daemon access) and is mitigated by the systemd dependency that
> prevents Docker from starting without the mount. However, NFS interruptions
> (network loss, PVE reboot) will stall Docker I/O until the mount recovers.
>
> **Validate for your environment:** Test NFS failure modes by temporarily
> stopping NFS on the PVE host (`systemctl stop nfs-kernel-server`), observing
> Docker behavior, then restarting NFS and confirming containers resume. Verify
> this against your Docker CE version (tested with Docker 29.x on Ubuntu 24.04).
>
> **Safer alternative:** Mount NFS at a separate path (e.g., `/mnt/docker-volumes`)
> and create Docker volumes with explicit bind-mount driver options:
>
> ```yaml
> volumes:
>   my_data:
>     driver: local
>     driver_opts:
>       type: none
>       o: bind
>       device: /mnt/docker-volumes/my_data
> ```
>
> This keeps `metadata.db` local at the cost of per-volume configuration.

**Backup (consistent):**

```bash
# On Docker VM — stop containers for a consistent snapshot
ssh ansible@<VM_IP> 'sudo systemctl stop docker'

# On Proxmox host — archive with relative path
tar -czf docker-volumes-backup-$(date +%Y%m%d).tar.gz \
  -C /rpool/datastore/docker-pool volumes

# On Docker VM — restart Docker
ssh ansible@<VM_IP> 'sudo systemctl start docker'
```

**Restore:**

```bash
# On Docker VM — stop Docker before restoring
ssh ansible@<VM_IP> 'sudo systemctl stop docker'

# On Proxmox host — extract archive into target directory
tar -xzf docker-volumes-backup-YYYYMMDD.tar.gz \
  -C /rpool/datastore/docker-pool

# Verify ownership and permissions
chown -R root:root /rpool/datastore/docker-pool/volumes
chmod 711 /rpool/datastore/docker-pool/volumes

# On Docker VM — restart and verify
ssh ansible@<VM_IP> 'sudo systemctl start docker && sudo docker volume ls'
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
