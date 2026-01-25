# Nginx Proxy Manager Deployment Guide

Step-by-step deployment instructions for the NPM LXC container.

## Pre-Deployment Checklist

- [ ] Proxmox VE 8.x accessible
- [ ] HashiCorp Vault running and unsealed
- [ ] NetBox instance configured
- [ ] S3 bucket created for state storage
- [ ] SSH key pair generated

## Step 1: Vault Secrets

```bash
# Connect to Vault
export VAULT_ADDR="https://vault.example.com:8200"
vault login

# Store Proxmox root password
vault kv put secrets/proxmox/root password="your-password"

# Store NetBox API token
vault kv put secrets/proxmox/netbox_api_token token="your-token"

# Verify Transit engine (for state encryption)
vault secrets list | grep transit

# Verify Transit engine (for state encryption)
vault secrets list | grep transit
```

## Step 1.5: Host Permissions (Unprivileged Mode)

This container runs in **Unprivileged Mode** (UID 100000). The deployment script automatically fixes bind mount permissions using `fix_bind_mount_permissions.sh`.

- **Script Location**: `scripts/fix_bind_mount_permissions.sh` (injected from base template)
- **Target UIDs**: Mapped to `100000` (root) and `100900` (service user) on host
- **Target Directories**: `/data` (application data), `/etc/letsencrypt` (SSL certs)

> [!NOTE]
> Ensure the Proxmox host allows the SSH user to execute `chmod`/`chown` on the bind mount directories, or run as root.

## Step 2: Configure Terraform Variables

```bash
cd terraform

# Copy example files
cp terraform.tfvars.example terraform.tfvars
cp s3.backend.config.template s3.backend.config

# Edit variables
vim terraform.tfvars
```

Key variables to configure:

| Variable | Description | Example |
| ---------- | ------------- | --------- |
| `container_hostname` | Container name | `npm` |
| `container_id` | Proxmox VM ID | `110` |
| `network_ip` | Static IP | `192.168.1.110/24` |
| `container_memory` | RAM in MB | `2048` |

## Step 3: Configure S3 Backend

Edit `s3.backend.config`:

```hcl
bucket         = "your-terraform-state-bucket"
key            = "lxc_npm/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "terraform-locks"  # Optional
```

## Step 4: Deploy

### Interactive Mode

```bash
./deploy.sh
```

Select option `1) deploy` from the menu.

### CLI Mode

```bash
./deploy.sh deploy
```

## Step 5: Post-Deployment

1. **Access Admin UI**

   ```text
   http://<container-ip>:81
   ```

2. **Default Login**
   - Email: `admin@example.com`
   - Password: `changeme`

3. **Change Password**
   - Click on user menu → Change Details
   - Update email and password

4. **Configure First Proxy Host**
   - Dashboard → Proxy Hosts → Add Proxy Host
   - Set domain, forward hostname/IP, port
   - Enable SSL with Let's Encrypt

## Troubleshooting

### NPM Service Not Starting

```bash
# SSH into container
ssh ansible@<container-ip>

# Check service status
sudo systemctl status npm
sudo systemctl status openresty

# View logs
sudo journalctl -u npm -f
```

### SSL Certificate Issues

```bash
# Check certbot
sudo /opt/certbot/bin/certbot certificates

# Manual renewal
sudo /opt/certbot/bin/certbot renew
```

### Database Issues

```bash
# SQLite database location
ls -la /data/database.sqlite

# Backup database
sudo cp /data/database.sqlite /data/database.sqlite.backup
```

## Firewall Ports

Ensure these ports are open:

| Port | Direction | Purpose |
| ------ | ----------- | --------- |
| 80 | Inbound | HTTP traffic |
| 443 | Inbound | HTTPS traffic |
| 81 | Inbound | Admin UI |
| 22 | Inbound | SSH (management) |

---

**Last Updated**: January 2026
