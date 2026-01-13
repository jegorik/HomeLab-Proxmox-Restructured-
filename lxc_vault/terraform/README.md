# Terraform/OpenTofu Configuration - HashiCorp Vault LXC

This directory contains the Infrastructure as Code (IaC) configuration for deploying a HashiCorp Vault LXC container on Proxmox VE using OpenTofu (or Terraform).

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Configuration Files](#configuration-files)
- [Initial Setup](#initial-setup)
- [Deployment](#deployment)
- [Variables Reference](#variables-reference)
- [Outputs Reference](#outputs-reference)
- [State Management](#state-management)
- [Troubleshooting](#troubleshooting)

## 🔍 Overview

### Architecture Components

This Terraform configuration provisions:

1. **LXC Container** on Proxmox VE with Debian 13
2. **Network Configuration** (static IP or DHCP)
3. **SSH Access** with key-based authentication
4. **Ansible User** for automated configuration
5. **Random Password Generation** for security
6. **Remote State Storage** in S3 with encryption

### Provider Versions

| Provider | Version | Purpose |
|----------|---------|---------|
| `bpg/proxmox` | 0.89.1 | Proxmox VE management |
| `hashicorp/aws` | 6.26.0 | S3 backend |
| `hashicorp/random` | ~> 3.6 | Password generation |

**Note**: This configuration uses **OpenTofu 1.8+** features (state encryption). For Terraform compatibility, use version 1.7+, but encryption blocks will not work.

## 📦 Prerequisites

### 1. OpenTofu/Terraform Installation

```bash
# Install OpenTofu (recommended)
# See: https://opentofu.org/docs/intro/install/

# Or install Terraform
# See: https://developer.hashicorp.com/terraform/downloads
```

### 2. Proxmox VE Configuration

#### Create API Token

1. Log in to Proxmox web interface
2. Navigate to: **Datacenter → Permissions → API Tokens**
3. Click **Add** and create token:
   - User: `terraform@pve` (create user first if needed)
   - Token ID: `terraform-token`
   - Privilege Separation: ✅ Enabled

4. Required Permissions for token (Path: `/`):
   ```
   Datastore.AllocateSpace    # Allocate disk space
   Datastore.AllocateTemplate # Use CT templates
   Datastore.Audit           # View storage info
   SDN.Use                   # Use network
   Sys.Audit                 # View system info
   Sys.Console               # Required for remote-exec
   VM.Allocate               # Create containers
   VM.Audit                  # View containers
   VM.Config.CPU             # Configure CPU
   VM.Config.Disk            # Configure disks
   VM.Config.Memory          # Configure memory
   VM.Config.Network         # Configure network
   VM.Config.Options         # Configure options
   VM.PowerMgmt              # Start/stop containers
   ```

#### Download LXC Template

```bash
# SSH to Proxmox host
ssh root@proxmox-host

# Update template list
pveam update

# List available Debian templates
pveam available | grep debian

# Download Debian 13 template (recommended)
pveam download local debian-13-standard_13.1-2_amd64.tar.zst

# Verify download
pveam list local
```

### 3. AWS S3 Setup (for remote state)

#### Create S3 Bucket

```bash
# Using AWS CLI
aws s3api create-bucket \
  --bucket your-terraform-state-bucket \
  --region us-east-1 \
  --profile tofu-aws-profile

# Enable versioning (required for state history)
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-terraform-state-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket your-terraform-state-bucket \
  --public-access-block-configuration \
    BlockPublicAcls=true,\
    IgnorePublicAcls=true,\
    BlockPublicPolicy=true,\
    RestrictPublicBuckets=true
```

#### Configure AWS Credentials

```bash
# Configure AWS profile
aws configure --profile tofu-aws-profile
# AWS Access Key ID: [Enter your key]
# AWS Secret Access Key: [Enter your secret]
# Default region name: us-east-1
# Default output format: json

# Verify credentials
aws sts get-caller-identity --profile tofu-aws-profile
```

### 4. SSH Key Generation

```bash
# Generate SSH key for root access
ssh-keygen -t ed25519 -C "vault-lxc-root" -f ~/.ssh/pve_ssh

# Generate SSH key for Ansible user (recommended: separate key)
ssh-keygen -t ed25519 -C "ansible@vault" -f ~/.ssh/ansible

# Set proper permissions
chmod 600 ~/.ssh/pve_ssh ~/.ssh/ansible
chmod 644 ~/.ssh/pve_ssh.pub ~/.ssh/ansible.pub
```

## 📁 Configuration Files

### File Descriptions

| File | Purpose |
|------|---------|
| `main.tf` | LXC container resource definition |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output value definitions |
| `providers.tf` | Provider configurations |
| `backend.tf` | S3 backend and provider versions |
| `encryption.tf` | State file encryption (OpenTofu) |
| `terraform.tfvars` | Variable values (create from example) |
| `s3.backend.config` | S3 backend configuration (create from template) |

### Configuration Relationships

```
terraform.tfvars ──→ variables.tf ──→ main.tf ──→ outputs.tf
                                        ↓
                                   Container Created
                                        ↓
s3.backend.config ──→ backend.tf ──→ State Stored (S3)
                                        ↓
encryption.tf ──────────────────→ State Encrypted
```

## 🚀 Initial Setup

### Step 1: Create Configuration Files

```bash
cd terraform

# Create Terraform variables from example
cp terraform.tfvars.example terraform.tfvars

# Create S3 backend configuration from template
cp s3.backend.config.template s3.backend.config

# Edit both files with your values
vim terraform.tfvars
vim s3.backend.config
```

### Step 2: Configure State Encryption Passphrase

```bash
# Generate strong passphrase (32 characters, base64 encoded)
openssl rand -base64 32 > ~/.ssh/state_passphrase

# Set proper permissions
chmod 600 ~/.ssh/state_passphrase

# Verify file created
ls -la ~/.ssh/state_passphrase
```

### Step 3: Initialize Terraform

```bash
# Initialize with S3 backend
tofu init -backend-config=s3.backend.config

# You should see:
# ✓ Backend initialized
# ✓ Providers installed
# ✓ Modules installed (if any)
```

**Important**: The `tofu init` command must be run with `-backend-config` flag because backend blocks cannot use variable interpolation.

## 🚀 Deployment

### Deployment Commands

```bash
# 1. Validate configuration
tofu validate

# 2. Format code (optional but recommended)
tofu fmt

# 3. Review planned changes
tofu plan

# 4. Apply configuration
tofu apply

# 5. View outputs
tofu output

# 6. Get specific output values
tofu output vault_url
tofu output -raw lxc_root_password
tofu output -raw ansible_inventory_entry
```

### Typical Deployment Output

```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

ansible_inventory_entry = <<EOT
vault:
  ansible_host: 10.0.100.50
  ansible_user: ansible
  ansible_ssh_private_key_file: ~/.ssh/ansible
  ansible_python_interpreter: /usr/bin/python3
EOT
lxc_hostname = "vault"
lxc_id = 109
lxc_ip_address = "10.0.100.50/24"
ssh_command = "ssh root@10.0.100.50"
vault_url = "http://10.0.100.50:8200"
```

### Container Lifecycle Management

```bash
# Update container (modify terraform.tfvars, then apply)
tofu apply

# Destroy container (WARNING: Deletes all data!)
tofu destroy

# Show current state
tofu show

# List resources
tofu state list

# Refresh state (sync with actual infrastructure)
tofu refresh
```

## 📊 Variables Reference

### Essential Variables

#### Proxmox Connection

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `proxmox_endpoint` | string | ✅ | - | Proxmox API endpoint (e.g., `https://192.168.1.100:8006`) |
| `proxmox_api_token` | string | ✅ | - | API token: `user@realm!token_id=secret` |
| `proxmox_node` | string | ❌ | `"pve"` | Proxmox node name |
| `connection_insecure` | bool | ❌ | `true` | Skip TLS verification (for self-signed certs) |

#### Container Identity

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `lxc_id` | number | ❌ | `200` | Container VMID (100-999999999) |
| `lxc_hostname` | string | ❌ | `"vault"` | Container hostname |
| `lxc_description` | string | ❌ | `"HashiCorp Vault..."` | Description in Proxmox GUI |
| `lxc_tags` | list(string) | ❌ | `["vault", "secrets", "tofu-managed"]` | Container tags |

#### Resources

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `lxc_cpu_cores` | number | ❌ | `1` | CPU cores (1-128) |
| `lxc_memory` | number | ❌ | `1024` | Memory in MB (min: 512) |
| `lxc_swap` | number | ❌ | `512` | Swap in MB (0 to disable) |
| `lxc_disk_size` | number | ❌ | `8` | Root disk size in GB (min: 4) |
| `lxc_disk_storage` | string | ❌ | `"local-lvm"` | Storage pool for rootfs |

#### Network

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `lxc_ip_address` | string | ❌ | `"dhcp"` | IP with CIDR (e.g., `10.0.100.50/24`) or `dhcp` |
| `lxc_gateway` | string | ❌ | `""` | Gateway IP (required for static IP) |
| `lxc_dns_servers` | string | ❌ | `"8.8.8.8 8.8.4.4"` | Space-separated DNS servers |
| `lxc_network_bridge` | string | ❌ | `"vmbr0"` | Network bridge name |

#### Security

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `lxc_unprivileged` | bool | ❌ | `true` | Run as unprivileged container |
| `lxc_protection` | bool | ❌ | `false` | Protect from accidental deletion |
| `ssh_public_key_path` | string | ❌ | `"~/.ssh/id_rsa.pub"` | SSH public key for root |
| `ssh_private_key_path` | string | ❌ | `"~/.ssh/id_rsa"` | SSH private key for provisioning |

#### Ansible User

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `ansible_user_enabled` | bool | ❌ | `false` | Enable Ansible user creation |
| `ansible_user_name` | string | ❌ | `"ansible"` | Ansible username |
| `ansible_ssh_public_key_path` | string | ❌ | `"~/.ssh/ansible_rsa.pub"` | SSH public key for Ansible |
| `ansible_user_sudo` | bool | ❌ | `true` | Grant passwordless sudo |
| `ansible_user_sudo_commands` | list(string) | ❌ | `[]` | Limited sudo commands (empty = all) |

#### State Encryption

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `passphrase` | string | ❌ | `"~/.ssh/state_passphrase"` | Path to passphrase file |
| `key_length` | number | ❌ | `32` | Encryption key length (bytes) |
| `key_iterations` | number | ❌ | `600000` | PBKDF2 iterations |
| `key_hash_function` | string | ❌ | `"sha512"` | Hash function (`sha256` or `sha512`) |

### Variable Validation

Variables include built-in validation to prevent common errors:

```hcl
# Example validations:
- proxmox_endpoint must use HTTPS
- lxc_id must be 100-999999999
- lxc_hostname must be valid DNS name
- lxc_cpu_cores must be 1-128
- lxc_memory minimum 512MB
- lxc_disk_size minimum 4GB
- lxc_ip_address format validated
- ansible_user_sudo_commands must be absolute paths
```

## 📤 Outputs Reference

### Available Outputs

| Output | Sensitive | Description |
|--------|-----------|-------------|
| `lxc_id` | ❌ | Container VMID |
| `lxc_hostname` | ❌ | Container hostname |
| `lxc_node` | ❌ | Proxmox node name |
| `lxc_ip_address` | ❌ | Container IP address |
| `vault_url` | ❌ | Vault web UI URL |
| `lxc_root_password` | ✅ | Container root password |
| `ssh_command` | ❌ | SSH command for root access |
| `ansible_user_enabled` | ❌ | Whether Ansible user was created |
| `ansible_ssh_command` | ❌ | SSH command for Ansible user |
| `ansible_inventory_entry` | ❌ | Ready-to-use Ansible inventory YAML |
| `resource_summary` | ❌ | Resource allocation summary |

### Retrieving Outputs

```bash
# View all non-sensitive outputs
tofu output

# Get specific output
tofu output vault_url

# Get sensitive output (e.g., password)
tofu output -raw lxc_root_password

# Get output as JSON
tofu output -json

# Save Ansible inventory to file
tofu output -raw ansible_inventory_entry > ../ansible/inventory.yml
```

## 💾 State Management

### State File Location

- **Local**: `.terraform/terraform.tfstate` (if no backend configured)
- **Remote**: S3 bucket specified in `s3.backend.config`

### State Encryption

This configuration uses OpenTofu's native state encryption with:

- **Key Derivation**: PBKDF2 with 600,000 iterations
- **Hash Function**: SHA-512
- **Encryption**: AES-GCM-256
- **Passphrase Location**: `~/.ssh/state_passphrase` (default)

**Security Note**: The passphrase file must exist and be readable. If lost, state file cannot be decrypted!

### State Operations

```bash
# View current state
tofu state list

# Show specific resource
tofu state show proxmox_virtual_environment_container.vault

# Remove resource from state (doesn't delete actual resource)
tofu state rm proxmox_virtual_environment_container.vault

# Import existing container
tofu import proxmox_virtual_environment_container.vault pve/lxc/109

# Pull remote state to local
tofu state pull > state-backup.json

# Unlock state (if stuck after crash)
tofu force-unlock <lock-id>
```

### State Backup

```bash
# Manual backup
tofu state pull > backups/state-$(date +%Y%m%d-%H%M%S).json

# S3 versioning provides automatic backups
aws s3api list-object-versions \
  --bucket your-terraform-state-bucket \
  --prefix vault.tfstate
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Backend Initialization Fails

**Error**: `Error: Failed to get existing workspaces`

**Solutions**:
```bash
# Verify S3 bucket exists
aws s3 ls s3://your-bucket-name --profile tofu-aws-profile

# Check AWS credentials
aws sts get-caller-identity --profile tofu-aws-profile

# Verify backend config file
cat s3.backend.config

# Re-initialize with fresh backend config
tofu init -reconfigure -backend-config=s3.backend.config
```

#### 2. State Encryption Errors

**Error**: `Error: Failed to decrypt state`

**Solutions**:
```bash
# Verify passphrase file exists
ls -la ~/.ssh/state_passphrase

# Check file is not empty
cat ~/.ssh/state_passphrase

# Verify permissions
chmod 600 ~/.ssh/state_passphrase

# If passphrase lost, state cannot be recovered!
# You must recreate from scratch or use backup
```

#### 3. Proxmox API Authentication Fails

**Error**: `Error: authentication failed`

**Solutions**:
```bash
# Test API token manually
curl -k -H "Authorization: PVEAPIToken=user@pam!token=secret" \
  https://proxmox-ip:8006/api2/json/version

# Verify token hasn't expired
# Check Proxmox GUI: Datacenter → Permissions → API Tokens

# Ensure token has required permissions
# See Prerequisites section above
```

#### 4. Template Not Found

**Error**: `Error: template file not found`

**Solutions**:
```bash
# SSH to Proxmox host
ssh root@proxmox-host

# List available templates
pveam list local

# Download if missing
pveam download local debian-13-standard_13.1-2_amd64.tar.zst

# Update terraform.tfvars with correct filename
vim terraform.tfvars
# lxc_template_file = "debian-13-standard_13.1-2_amd64.tar.zst"
```

#### 5. Container Creation Hangs

**Error**: Container creation starts but never completes

**Solutions**:
```bash
# Check Proxmox logs
ssh root@proxmox-host tail -f /var/log/pve/tasks/active/*

# Verify storage has space
ssh root@proxmox-host pvesm status

# Check network bridge exists
ssh root@proxmox-host brctl show

# Manually delete stuck container
ssh root@proxmox-host pct destroy <vmid>

# Then retry
tofu apply
```

#### 6. SSH Provisioner Fails

**Error**: `Error: timeout waiting for SSH`

**Solutions**:
```bash
# Verify container IP is reachable
ping <container-ip>

# Check SSH key permissions
chmod 600 ~/.ssh/pve_ssh

# Test manual SSH connection
ssh -i ~/.ssh/pve_ssh root@<container-ip>

# Verify container is running
ssh root@proxmox-host pct list | grep <vmid>

# Check container networking
ssh root@proxmox-host pct exec <vmid> -- ip addr
```

#### 7. Mount Point Errors

**Error**: `Error: mount point configuration failed`

**Note**: The variable `lxc_mount_point_path` is defined but currently not used in main.tf (line 119 uses hardcoded path). This is a known issue.

**Workaround**:
```bash
# Manually configure mount point after creation
ssh root@proxmox-host pct set <vmid> -mp0 /host/path,mp=/container/path
```

### Debug Mode

Enable detailed logging:

```bash
# OpenTofu/Terraform debug mode
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log
tofu apply

# View debug log
tail -f terraform-debug.log
```

### Validation Commands

```bash
# Validate configuration syntax
tofu validate

# Check formatting
tofu fmt -check

# Plan without applying
tofu plan -out=tfplan

# Show plan in detail
tofu show tfplan
```

## 🔒 Security Best Practices

### Secrets Management

1. **Never commit sensitive files**:
   - ❌ `terraform.tfvars`
   - ❌ `s3.backend.config`
   - ❌ `~/.ssh/state_passphrase`
   - ❌ `.terraform/terraform.tfstate`

2. **Use environment variables** (alternative to tfvars):
   ```bash
   export TF_VAR_proxmox_api_token="user@pam!token=secret"
   export TF_VAR_lxc_root_password="secure-password"
   ```

3. **Rotate credentials regularly**:
   - Proxmox API tokens: Every 90 days
   - SSH keys: Every 180 days
   - State encryption passphrase: Every 180 days

### State Security

1. **S3 Bucket Security**:
   - ✅ Enable versioning
   - ✅ Enable encryption at rest
   - ✅ Block public access
   - ✅ Use bucket policies for access control
   - ✅ Enable CloudTrail logging

2. **State File Encryption**:
   - ✅ Use strong passphrase (32+ characters)
   - ✅ Store passphrase securely (outside repo)
   - ✅ Backup passphrase in password manager
   - ✅ Use PBKDF2 with high iterations (600k+)

3. **Access Control**:
   - ✅ Use separate AWS IAM users/roles for Terraform
   - ✅ Apply principle of least privilege
   - ✅ Use MFA for AWS console access
   - ✅ Audit state file access regularly

## 📚 Additional Resources

### Official Documentation

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/)
- [HashiCorp Vault](https://developer.hashicorp.com/vault/docs)

### Community Resources

- [OpenTofu GitHub](https://github.com/opentofu/opentofu)
- [Proxmox Forum](https://forum.proxmox.com/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

---

**Note**: This configuration is designed for homelab and development environments. For production use, implement additional security hardening, monitoring, and disaster recovery procedures.

**Last Updated**: January 2026

