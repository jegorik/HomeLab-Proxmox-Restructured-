# Proxmox Backup Server - Deployment Guide

Step-by-step guide for deploying Proxmox Backup Server in an LXC container.

## Prerequisites

### Required Software

```bash
# OpenTofu (recommended) or Terraform
# Install OpenTofu: https://opentofu.org/docs/intro/install/

# Ansible
pip install ansible

# Vault CLI (optional, for secret management)
# https://developer.hashicorp.com/vault/install
```

### Infrastructure Requirements

- Proxmox VE 8.x with API access
- HashiCorp Vault (running and unsealed)
- NetBox instance with API access (optional)
- SSH key pair for Ansible access

### PBS-Specific Requirements

> [!IMPORTANT]
> This container runs as an **unprivileged container** (`lxc_unprivileged = true`) by default.
> The deployment script automatically fixes bind mount permissions using `fix_bind_mount_permissions.sh` to map the host UID/GID correctly.

Ensure the bind mount directories exist on the Proxmox host:

```bash
# Create directories on Proxmox host
mkdir -p /rpool/data/pbs-config
mkdir -p /rpool/data/pbs-backups
```

---

## Step 1: Configure Vault Secrets

Store required secrets in your Vault instance (paths can be customized in `variables.tf`):

```bash
# Set Vault address
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs.xxxxx"

# Store Proxmox root password
vault kv put secret/proxmox/root password="your-pve-password"

# Store NetBox API token
vault kv put secret/netbox/api api_token="your-netbox-token"
```

---

## Step 2: Configure Terraform Variables

```bash
# Copy example file
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit with your values
vim terraform/terraform.tfvars
```

### Required Variables

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `vault_address` | Vault server URL | `https://vault.example.com:8200` |
| `lxc_id` | LXC VMID | `107` |
| `lxc_hostname` | Hostname | `pbs` |
| `lxc_ip_address` | IP with CIDR | `192.0.2.107/24` |
| `lxc_disk_storage` | Storage Pool | `local-zfs` |
| `lxc_pbs_config_mount_volume` | Host path for PBS config | `/rpool/data/pbs-config` |
| `lxc_pbs_datastore_mount_volume` | Host path for backups | `/rpool/data/pbs-backups` |

---

## Step 3: Configure State Backend (Recommended)

To use S3 backend for state storage:

```bash
cp terraform/s3.backend.config.template terraform/s3.backend.config
vim terraform/s3.backend.config
```

Then `deploy.sh` will automatically detect and use it.

---

## Step 4: Deploy

### Interactive Mode

```bash
./deploy.sh
```

### Command Line

```bash
# Dry-run first
./deploy.sh plan

# If plan looks good, deploy
./deploy.sh deploy
```

---

## Step 5: Verify Deployment

```bash
# Check status
./deploy.sh status

# SSH into container
ssh ansible@192.0.2.107

# Check PBS services
systemctl status proxmox-backup proxmox-backup-proxy
```

### Access PBS Web UI

Open in browser: `https://<container-ip>:8007`

Default credentials: Use the Proxmox host's `root@pam` or create a PBS user.

---

## Troubleshooting

### Vault Connection Failed

```bash
# Check Vault is reachable
curl -k ${VAULT_ADDR}/v1/sys/health

# Verify token is valid
vault token lookup
```

### Terraform Apply Failed

```bash
# Check Proxmox credentials
vault kv get secret/proxmox/root

# Verify API URL is correct
# Check `proxmox_endpoint_vault_path` variable
```

### Ansible Connectivity Failed

```bash
# Test SSH manually
ssh ansible@<container-ip>

# Check known_hosts
ssh-keygen -R <container-ip>
```

### PBS Service Failed to Start

This is usually caused by permission issues on the bind-mounted `/etc/proxmox-backup` directory.

```bash
# Check service logs
journalctl -xeu proxmox-backup.service

# Fix permissions (if needed)
sudo chown -R backup:backup /etc/proxmox-backup
sudo chmod 700 /etc/proxmox-backup
sudo systemctl restart proxmox-backup proxmox-backup-proxy
```

### Apt Update 401 Unauthorized

If you see errors fetching from `enterprise.proxmox.com`:

```bash
# Remove enterprise repository
sudo rm -f /etc/apt/sources.list.d/pbs-enterprise.sources
sudo apt update
```

---

## Customization

### Adding Ansible Roles

1. Create role in `ansible/roles/`
2. Add to `ansible/site.yml`
3. Run Ansible only: `./deploy.sh ansible`

### Modifying Container Resources

Edit `terraform/terraform.tfvars`:

```hcl
lxc_memory    = 8192  # MB
lxc_cpu_cores = 8
lxc_disk_size = 32    # GB
```

---

## Cleanup

```bash
# Destroy infrastructure
./deploy.sh destroy

# Clean local files
rm -f terraform/terraform.tfstate*
rm -f ansible/inventory.yml
```

> [!WARNING]
> Destroying the container does **not** delete the bind mount data. To fully clean up, also remove:
>
> ```bash
> rm -rf /rpool/data/pbs-config
> rm -rf /rpool/data/pbs-backups
> ```
