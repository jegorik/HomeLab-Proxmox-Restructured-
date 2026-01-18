# LXC Base Template - Deployment Guide

Step-by-step guide for deploying LXC containers using this template.

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

Store required secrets in your Vault instance:

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
| `pve_api_url` | Proxmox API URL | `https://192.168.1.100:8006/api2/json` |
| `netbox_url` | NetBox server URL | `https://netbox.example.com` |
| `container_id` | LXC VMID | `200` |
| `container_hostname` | Hostname | `my-container` |
| `network_ip` | IP with CIDR | `192.168.1.200/24` |
| `network_gateway` | Gateway IP | `192.168.1.1` |
| `ssh_public_key` | SSH public key | `ssh-ed25519 AAAA...` |

---

## Step 3: Deploy

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

## Step 4: Verify Deployment

```bash
# Check status
./deploy.sh status

# SSH into container
ssh ansible@192.168.1.200

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
curl -k ${PVE_API_URL}/version
```

### Ansible Connectivity Failed

```bash
# Test SSH manually
ssh ansible@<container-ip>

# Check known_hosts
ssh-keygen -R <container-ip>
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
container_memory    = 4096  # MB
container_cores     = 4
container_disk_size = "20G"
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
