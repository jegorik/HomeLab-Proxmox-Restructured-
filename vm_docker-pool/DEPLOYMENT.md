# =============================================================================
# VM Docker Pool - Deployment Guide
# =============================================================================
#
# Step-by-step guide to deploy Ubuntu Server 24.04.3 LTS VM with Docker
# and Portainer for container management.
#
# Last Updated: January 2026
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

### 4. Portainer Data Directory

The deployment script will create `/rpool/datastore/portainer` on the Proxmox
host. Ensure this path exists and is writable, or modify `portainer_bind_mount_source`
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
| `vm_ip_address` | Static IP with CIDR | `192.168.0.200/24` |
| `vm_gateway` | Default gateway | `192.168.0.1` |
| `vm_cpu_cores` | CPU cores | `2` |
| `vm_memory` | Memory in MB | `4096` |
| `vm_disk_size` | Disk size in GB | `32` |

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
ssh ansible@192.168.0.200

# Verify Docker
docker --version
docker compose version

# Verify Portainer
docker ps | grep portainer
```

### Step 4: Configure Portainer

1. Open https://192.168.0.200:9443 in your browser
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
   - Forward Hostname: `192.168.0.200`
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

### Backup Portainer Data

Portainer data is stored in `/rpool/datastore/portainer` on the Proxmox host.
This persists across VM redeployments.

To backup:

```bash
# On Proxmox host
tar -czvf portainer-backup-$(date +%Y%m%d).tar.gz /rpool/datastore/portainer
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
3. Test manually: `ssh -i ~/.ssh/ansible ansible@192.168.0.200`

### Portainer Not Accessible

1. Verify Docker is running: `systemctl status docker`
2. Check Portainer container: `docker ps -a | grep portainer`
3. Check container logs: `docker logs portainer`
4. Verify UFW allows port 9443: `sudo ufw status`

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
# Destroy VM (data in /rpool/datastore/portainer preserved)
./deploy.sh destroy

# Redeploy
./deploy.sh deploy
```

Data will be automatically restored from the bind mount on next deployment.
