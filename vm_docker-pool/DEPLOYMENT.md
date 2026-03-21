# =============================================================================
# VM Docker Pool - Deployment Guide
# =============================================================================
#
# Step-by-step guide to deploy Ubuntu Server 24.04.3 LTS VM with Docker
# and Portainer for container management.
#
# Last Updated: March 2026
# =============================================================================

## Prerequisites

### 1. Required Tools

Ensure the following tools are installed on your deployment machine:

- OpenTofu >= 1.0.0 or Terraform >= 1.5.0
- Ansible >= 2.15
- HashiCorp Vault CLI
- jq
- SSH client

### 2. Proxmox Requirements

- Proxmox VE 8.x or later
- Storage pool for VM disks (e.g., local-lvm)
- Network bridge configured (e.g., vmbr0)
- Cloud image storage enabled on "local" storage

### 3. Vault Secrets

Create the required secrets in Vault:

```bash
# Proxmox connection
vault kv put secret/proxmox/endpoint url="https://proxmox.example.local:8006"
vault kv put secret/proxmox/node node_name="pve"
vault kv put secret/proxmox/root username="root@pam"
vault kv put secret/proxmox/root password="your-password"

# SSH keys
vault kv put secret/ssh/ansible public_key="ssh-ed25519 AAAA..."
vault kv put secret/ssh/root private_key="-----BEGIN OPENSSH PRIVATE KEY-----..."

# NetBox (if using DCIM registration)
vault kv put secret/netbox/api_token token="your-netbox-token"

# AWS S3 backend (if using remote state)
vault kv put secret/aws/s3 bucket="your-terraform-state-bucket"
```

### 4. Docker Volumes NFS Directory

The deployment creates an NFS export at `/rpool/datastore/docker-pool/volumes` on
the Proxmox host. This directory is mounted at `/var/lib/docker/volumes` inside
the VM, so ALL Docker named volumes are automatically persisted on PVE ZFS storage.

The Terraform provisioner handles NFS server installation and export setup
automatically. If you want to change the export path, modify `docker_volumes_nfs_path`
in terraform.tfvars.

---

## Deployment Steps

### Step 1: Configure Variables

```bash
cd vm_docker-pool/terraform

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars
cp s3.backend.config.template s3.backend.config

# Edit with your values
nano terraform.tfvars
nano s3.backend.config
```

Key variables to configure:

| Variable | Description | Example |
| ---------- | ------------- | --------- |
| `vault_address` | Vault server URL | `https://vault.local:8200` |
| `vm_id` | Unique VM ID | `300` |
| `vm_hostname` | VM hostname | `docker-pool` |
| `vm_ip_address` | Static IP with CIDR | `198.51.100.200/24` |
| `vm_gateway` | Default gateway | `198.51.100.1` |
| `vm_cpu_cores` | CPU cores | `2` |
| `vm_memory` | Memory in MB | `4096` |
| `vm_disk_size` | Disk size in GB | `32` |
| `docker_volumes_nfs_path` | PVE export path | `/rpool/datastore/docker-pool/volumes` |
| `docker_volumes_nfs_subnet` | Allowed NFS subnet | `198.51.100.0/24` |

### Step 2: Deploy Infrastructure

```bash
cd vm_docker-pool

# Make deploy script executable
chmod +x deploy.sh

# Run full deployment (interactive)
./deploy.sh

# Or run specific command
./deploy.sh deploy  # Full deployment
./deploy.sh plan    # Dry-run only
```

### Step 3: Verify Deployment

```bash
# Check status
./deploy.sh status

# SSH to VM
ssh ansible@198.51.100.200

# Verify Docker
docker --version
docker compose version

# Verify Portainer
docker ps | grep portainer
```

### Step 4: Configure Portainer

1. Open https://198.51.100.200:9443 in your browser
2. Accept the self-signed certificate warning
3. Create an admin user and strong password
4. Select "Docker - Manage the local Docker environment"
5. Start deploying containers!

---

## Post-Deployment

### Configure NPM Reverse Proxy (Optional)

To access Portainer via HTTPS with a valid certificate:

1. Login to Nginx Proxy Manager (lxc_npm)
2. Add a new Proxy Host:
   - Domain: `portainer.example.local`
   - Forward Hostname: `198.51.100.200`
   - Forward Port: `9443`
   - Enable SSL with Let's Encrypt

### Firewall Rules

The base role configures UFW with these rules:

| Port | Protocol | Purpose |
|------|----------|---------|
| 22   | TCP      | SSH     |
| 9443 | TCP      | Portainer HTTPS |

To add additional ports (e.g., for Docker services):

```bash
# On the VM
sudo ufw allow 8080/tcp comment "My Service"
```

### Backup Docker Volumes

All Docker named volumes (Portainer, any deployed stacks) are stored on the PVE
host at `/rpool/datastore/docker-pool/volumes`. This ZFS dataset is covered by
PBS backup automatically.

Manual backup:

```bash
# On Proxmox host
tar -czf docker-volumes-backup-$(date +%Y%m%d).tar.gz \
  -C /rpool/datastore/docker-pool volumes
```

---

## Troubleshooting

### VM Not Booting

1. Check Proxmox console for boot errors
2. Verify cloud image downloaded correctly
3. Check cloud-init logs: `journalctl -u cloud-init`

### SSH Connection Refused

1. Wait for cloud-init to complete (2-3 minutes)
2. Verify SSH key was injected: `grep -r "ansible" /home/`
3. Check cloud-init logs: `cat /var/log/cloud-init-output.log`

### Ansible Connectivity Failed

1. Verify VM IP is correct in inventory.yml
2. Check SSH key permissions: `chmod 600 ~/.ssh/ansible`
3. Test manually: `ssh -i ~/.ssh/ansible ansible@198.51.100.200`

### Portainer Not Accessible

1. Verify Docker is running: `systemctl status docker`
2. Check Portainer container: `docker ps -a | grep portainer`
3. Check container logs: `docker logs portainer`
4. Verify UFW allows port 9443: `sudo ufw status`

### NFS Mount Issues

1. Verify NFS export on PVE host: `showmount -e localhost`
2. Check mount status on VM: `mountpoint -q /var/lib/docker/volumes && echo mounted || echo not-mounted`
3. Verify NFS client installed: `dpkg -l | grep nfs-common`
4. Check systemd mount: `systemctl status var-lib-docker-volumes.mount`
5. Verify Docker depends on NFS: `systemctl cat docker.service.d/nfs-volumes.conf`

### Docker Permission Denied

1. Verify user is in docker group: `groups ansible`
2. Re-login to apply group changes: `su - ansible`
3. Or reboot the VM

---

## Maintenance

### Update Portainer

```bash
# On the VM
cd /opt/portainer
docker compose pull
docker compose up -d
```

### Update Docker

```bash
# On the VM
sudo apt update
sudo apt upgrade docker-ce docker-ce-cli containerd.io
```

### Recreate VM (Preserving Data)

```bash
# Destroy VM (Docker volumes on PVE NFS are preserved)
./deploy.sh destroy

# Redeploy
./deploy.sh deploy
```

All Docker named volumes survive VM reinstall because they live on the PVE host
at `/rpool/datastore/docker-pool/volumes`. New VM auto-mounts via NFS.

---

## Migrating an Existing Server (Plan B)

If you already have a running `vm_docker-pool` server using local Docker volumes
(not NFS), use the migration script to move volumes to NFS without data loss:

```bash
cd vm_docker-pool

# Dry run first (shows what will happen, no changes)
DRY_RUN=true ./scripts/migrate_to_nfs_volumes.sh

# Run actual migration (interactive, asks for confirmations)
./scripts/migrate_to_nfs_volumes.sh
```

The script handles:
1. **Phase 1**: Install NFS server on PVE and configure export (no downtime)
2. **Phase 2**: Install NFS client on VM and pre-copy volumes (no downtime)
3. **Phase 3**: Stop Docker, final sync, mount NFS at `/var/lib/docker/volumes` (~2-5 min downtime)
4. **Phase 4**: Update Portainer to named volume
5. **Phase 5**: Start services and verify

Environment variables for customization:
- `PVE_HOST` — PVE host IP (default: 198.51.100.1)
- `VM_HOST` — Docker VM IP (default: 198.51.100.200)
- `NFS_PATH` — NFS export path (default: /rpool/datastore/docker-pool/volumes)
- `NFS_SUBNET` — Allowed subnet (default: 198.51.100.0/24)

After migration, old volumes are preserved at `/var/lib/docker/volumes.old`.
Remove after confirming stability: `ssh ansible@<VM_IP> 'sudo rm -rf /var/lib/docker/volumes.old'`
