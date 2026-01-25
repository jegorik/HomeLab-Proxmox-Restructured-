# InfluxDB LXC - Deployment Guide

Detailed deployment instructions for the InfluxDB LXC container project.

## Prerequisites

### Required Infrastructure

- **Proxmox VE 8.x** with LXC template downloaded
- **HashiCorp Vault** deployed and unsealed ([lxc_vault](../lxc_vault/README.md))
- **NetBox** deployed (optional, for IPAM registration)

### Required Software (Control Machine)

| Tool | Version | Installation |
| ---- | ------- | ------------ |
| OpenTofu | 1.8+ | [opentofu.org](https://opentofu.org/) |
| Ansible | 2.15+ | `pip install ansible` |
| Vault CLI | 1.13+ | [vaultproject.io](https://www.vaultproject.io/) |
| jq | 1.6+ | `apt install jq` |

### Vault Setup

Ensure the following are configured in Vault:

1. **Transit Engine** for state encryption:

   ```bash
   vault secrets enable transit
   vault write -f transit/keys/tofu-state-encryption
   ```

2. **KV v2 Secrets** with required paths:

   ```bash
   # Proxmox credentials
   vault kv put secrets/proxmox/proxmox_endpoint url="https://192.168.1.100:8006"
   vault kv put secrets/proxmox/proxmox_node_name node_name="pve"
   vault kv put secrets/proxmox/pve_root_password password="..."
   
   # SSH keys
   vault kv put secrets/proxmox/root_ssh_public_key key="ssh-rsa ..."
   vault kv put secrets/proxmox/root_ssh_private_key key="-----BEGIN OPENSSH..."
   vault kv put secrets/proxmox/ansible_ssh_public_key key="ssh-rsa ..."
   
   # NetBox (optional)
   vault kv put secrets/proxmox/netbox_api_token token="..."
   ```

3. **Userpass Authentication**:

   ```bash
   vault auth enable userpass
   vault write auth/userpass/users/tofu_admin password="..." policies="terraform"
   ```

### Host Preparation

Create the bind mount directory on the Proxmox host:

```bash
ssh root@<proxmox-host>
mkdir -p /rpool/datastore/influxdb
```

### Host Permissions (Unprivileged Mode)

This container runs in **Unprivileged Mode** (UID 100000). The deployment script automatically fixes bind mount permissions using `fix_bind_mount_permissions.sh`.

- **Script Location**: `scripts/fix_bind_mount_permissions.sh` (injected from base template)
- **Target UIDs**: Mapped to `100000` (root) and `100900` (influxdb user) on host
- **Target Directories**: `/rpool/datastore/influxdb`

> [!NOTE]
> Ensure the Proxmox host allows the SSH user to execute `chmod`/`chown` on the bind mount directories, or run as root.

## Step-by-Step Deployment

### 1. Configure Terraform Variables

```bash
cd lxc_influxdb
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# Vault
vault_address  = "https://vault.example.com:8200"
vault_username = "tofu_admin"

# Container
lxc_id         = 102
lxc_hostname   = "influxdb"
lxc_ip_address = "192.168.0.102/24"
lxc_gateway    = "192.168.0.1"

# Bind mount (adjust path for your setup)
lxc_influxdb_data_mount_volume = "/rpool/datastore/influxdb"
```

### 2. Configure S3 Backend (Optional)

```bash
cp terraform/s3.backend.config.template terraform/s3.backend.config
```

Edit with your S3 bucket details.

### 3. Deploy

```bash
./deploy.sh deploy
```

The script will:

1. Authenticate with Vault
2. Generate AWS credentials (if using S3 backend)
3. Initialize Terraform
4. Create LXC container
5. Run Ansible playbooks
6. Set up InfluxDB with initial admin user

### 4. Access InfluxDB

- **Web UI**: `http://<container-ip>:8086`
- **Default Credentials**: `admin` / `changeme123!` (change immediately!)

## Post-Deployment

### Change Admin Password

```bash
ssh ansible@<container-ip>
influx user password -n admin
```

### Create Additional Users

```bash
influx user create -n <username> -o homelab
```

### Create Buckets

```bash
influx bucket create -n metrics -r 30d -o homelab
```

## Troubleshooting

### Container Won't Start

**Cause**: Bind mount path doesn't exist on host.

**Solution**:

```bash
ssh root@<proxmox-host>
mkdir -p /rpool/datastore/influxdb
```

### InfluxDB Service Fails

**Cause**: Permission issues with bind mounts.

**Solution**: Verify host directory permissions. The deployment script should automatically set ownership to `100900:100900` (unprivileged `influxdb` user). Check logs if `fix_bind_mount_permissions.sh` failed.

### Initial Setup Already Done

The Ansible playbook checks if setup is needed via the `/api/v2/setup` endpoint. If InfluxDB was previously configured (data persisted in bind mounts), setup is skipped automatically.

### Connection Refused on Port 8086

**Cause**: InfluxDB not running or firewall blocking.

**Solution**:

```bash
ssh ansible@<container-ip>
sudo systemctl status influxdb
sudo ufw status
```

## Data Persistence

InfluxDB data is stored in a single bind mount:

| Data | Host Path | Container Path |
| ---- | --------- | -------------- |
| InfluxDB data | `/rpool/datastore/influxdb` | `/var/lib/influxdb` |

This includes BoltDB metadata (`influxd.bolt`) and time-series engine data (`engine/`). Data persists across container recreation.

## Backup Recommendations

1. **Proxmox Snapshots**: Use Proxmox backup for container-level backups
2. **InfluxDB Backup**: Use `influx backup` for database-level backups:

   ```bash
   influx backup /backup/influxdb-$(date +%Y%m%d)
   ```

## Maintenance

### Upgrade InfluxDB

```bash
ssh ansible@<container-ip>
sudo apt update
sudo apt upgrade influxdb2
sudo systemctl restart influxdb
```

### Check Logs

```bash
sudo journalctl -u influxdb -f
```
