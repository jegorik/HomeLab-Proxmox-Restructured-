# LXC Grafana Loki - Deployment Guide

Step-by-step guide for deploying Grafana Loki in an LXC container on Proxmox.

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

- Proxmox VE with API access
- HashiCorp Vault (running and unsealed)
- NetBox instance with API access
- SSH key pair for Ansible access

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
| ---------- | ------------- | --------- |
| `vault_address` | Vault server URL | `https://vault.example.com:8200` |
| `lxc_id` | LXC VMID | `108` |
| `lxc_hostname` | Hostname | `grafana-loki` |
| `lxc_ip_address` | IP with CIDR | `192.0.2.108/24` |
| `lxc_disk_storage` | Storage Pool | `local-zfs` |
| `lxc_grafana_loki_chunks_mount_volume` | Host path for chunks | `/rpool/datastore/grafana_loki/chunks` |
| `lxc_grafana_loki_rules_mount_volume` | Host path for rules | `/rpool/datastore/grafana_loki/rules` |
| `ansible_ssh_public_key_path` | SSH Public Key | `~/.ssh/ansible_rsa.pub` |

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
ssh ansible@192.0.2.108

# Verify Loki is running
curl -s http://192.0.2.108:3100/ready

# Check Loki metrics
curl -s http://192.0.2.108:3100/metrics | head

# View in NetBox
# Open: https://netbox.example.com/virtualization/virtual-machines/
```

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

### Loki Service Not Starting

```bash
# Check service status
ssh ansible@<container-ip>
sudo systemctl status loki
sudo journalctl -u loki --no-pager -n 50

# Validate config
loki -config.file=/etc/loki/config.yml -verify-config
```

### Bind Mount Permission Issues

```bash
# On Proxmox host - verify ownership
ls -la /rpool/datastore/grafana_loki/
# Should show 100900:100900

# Re-run permission fix if needed
./deploy.sh deploy
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
lxc_memory    = 2048  # MB
lxc_cpu_cores = 2
lxc_disk_size = 10    # GB
```

### Customizing Loki Configuration

Edit `ansible/roles/grafana_loki/defaults/main.yml`:

```yaml
loki_retention_period: "2160h"  # 90 days
loki_http_port: 3100
```

Then redeploy Ansible:

```bash
./deploy.sh ansible
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
