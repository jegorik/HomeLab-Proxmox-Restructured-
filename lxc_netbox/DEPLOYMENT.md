# Automated Deployment Guide

This guide covers the automated deployment script (`deploy.sh`) for the NetBox DCIM/IPAM LXC Container project with HashiCorp Vault integration.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Vault Integration](#vault-integration)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

## 🔍 Overview

The `deploy.sh` script is a professional-grade bash automation tool that handles the complete lifecycle of your NetBox infrastructure deployment on Proxmox. It integrates with HashiCorp Vault for secrets management and state encryption, combining pre-flight validation, interactive prompts, Terraform/OpenTofu provisioning, and Ansible configuration management into a single, user-friendly interface.

### Key Benefits

- ✅ **Zero Manual Steps**: Fully automated deployment from start to finish
- ✅ **Vault-Integrated**: Secure secrets management with HashiCorp Vault
- ✅ **Multi-Service Stack**: Coordinates PostgreSQL, Redis, NetBox, and Nginx
- ✅ **Intelligent Validation**: Comprehensive pre-flight checks including Vault connectivity
- ✅ **Interactive & Scriptable**: Works both interactively and in CI/CD pipelines
- ✅ **Safe Operations**: Multiple confirmation prompts for destructive actions
- ✅ **Detailed Logging**: Every action is logged with timestamps
- ✅ **Error Recovery**: Clear instructions when things go wrong

## 📦 Prerequisites

### Required Software

The script will check for these during pre-flight validation:

| Software | Purpose | Installation |
| ---------- | --------- | ------------- |
| **OpenTofu** or **Terraform** | Infrastructure provisioning | `brew install opentofu` or download from [opentofu.org](https://opentofu.org) |
| **Ansible** | Configuration management | `pip install ansible` |
| **SSH Client** | Remote access | Pre-installed on most systems |
| **jq** | JSON processing | `sudo apt install jq` |
| **Vault CLI** | Vault interaction | Download from [vaultproject.io](https://www.vaultproject.io/downloads) |

### Proxmox Setup

1. **Proxmox VE 8.x+** installed and accessible
2. **LXC Template** downloaded:

   ```bash
   pveam update
   pveam download local debian-13-standard_13.1-2_amd64.tar.zst
   ```

3. **Network Bridge** configured (usually `vmbr0`)

### SSH Keys

Generate SSH keys if you don't have them:

```bash
# For root access to container
ssh-keygen -t ed25519 -C "netbox-lxc-root" -f ~/.ssh/pve_ssh

# For Ansible automation
ssh-keygen -t ed25519 -C "ansible@netbox" -f ~/.ssh/ansible
```

### Configuration Files

1. **Terraform Variables**:

   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars  # Edit with your values
   ```

2. **S3 Backend** (optional, recommended for production):

   ```bash
   cp s3.backend.config.template s3.backend.config
   vim s3.backend.config  # Add S3 bucket configuration
   ```

## 🔐 Vault Integration

### Vault Deployment Order

**⚠️ IMPORTANT**: The [lxc_vault](../lxc_vault) project **MUST** be deployed first before deploying lxc_netbox.

See the [workspace root README](../README.md#deployment-order) for dependency information.

### Required Vault Setup

#### 1. Transit Engine for State Encryption

NetBox uses Vault's Transit encryption engine for Terraform state encryption:

```bash
# Enable Transit engine (already done if lxc_vault is deployed)
vault secrets enable transit

# Create encryption key for NetBox
vault write -f transit/keys/netbox
```

#### 2. KV Secrets for Proxmox Credentials

Store Proxmox credentials in Vault:

```bash
# Enable KV v2 secrets engine (already done if lxc_vault is deployed)
vault secrets enable -path=secrets kv-v2

# Store Proxmox credentials
vault kv put secrets/proxmox/credentials \
  endpoint="https://192.0.2.100:8006" \
  node="pve" \
  password="your-proxmox-password"

# Store NetBox-specific secrets
vault kv put secrets/netbox/config \
  secret_key="$(openssl rand -base64 64 | tr -d '\n')" \
  superuser_password="$(openssl rand -base64 32)"
```

#### 3. Authentication

Set up Vault authentication method (userpass example):

```bash
# Enable userpass authentication
vault auth enable userpass

# Create automation user
vault write auth/userpass/users/netbox-automation \
  password="secure-password" \
  policies="netbox-deploy"
```

#### 4. Vault Policy

Create a policy file `vault_policy.hcl` (see [vault_policy.hcl.example](vault_policy.hcl.example)):

```hcl
# Read Proxmox credentials
path "secrets/data/proxmox/*" {
  capabilities = ["read"]
}

# Read and write NetBox secrets
path "secrets/data/netbox/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Encrypt/decrypt state with Transit engine
path "transit/encrypt/netbox" {
  capabilities = ["update"]
}

path "transit/decrypt/netbox" {
  capabilities = ["update"]
}
```

Apply the policy:

```bash
vault policy write netbox-deploy vault_policy.hcl
```

### Vault Security Model

The deploy.sh script uses a simplified security model without credential caching:

- **Direct Vault authentication** - Tokens are obtained fresh each session
- **Environment variables** - VAULT_TOKEN is passed via environment (not command line)
- **No persistent cache** - Credentials are not stored on disk
- **Session-based** - Each deployment session authenticates independently

**Security Benefits**:

- ✅ No encrypted files to manage or rotate
- ✅ Credentials never persist on disk
- ✅ VAULT_TOKEN not visible in process list or logs
- ✅ Clean session isolation

### Vault Environment Variables

The deploy.sh script uses these Vault environment variables:

- `VAULT_ADDR`: Vault server URL (prompted if not set)
  - Set via: `export VAULT_ADDR="https://vault.example.com:8200"`
  - Or let script prompt you during deployment
  
- `VAULT_USERNAME`: Vault username for authentication (prompted if not set)
  - Set via: `export VAULT_USERNAME="your_username"`
  - Or let script prompt you during deployment
  
- `VAULT_TOKEN`: Vault authentication token (generated automatically)
- `TF_VAR_vault_password`: Vault password for OpenTofu provider (prompted during authentication)

**Recommended approach**: Set these environment variables in your shell or let the script prompt you interactively.

### Vault Pre-flight Checks

The deploy.sh script automatically verifies:

- ✅ Vault CLI is installed and accessible
- ✅ Vault server is reachable and unsealed
- ✅ Authentication succeeds
- ✅ Required secrets exist in Vault (SSH keys, passwords, config)
- ✅ Transit engine key exists for state encryption
- ✅ AWS dynamic credentials can be generated

## 🚀 Quick Start

### Interactive Mode (Recommended for First-Time Users)

```bash
# Navigate to project directory
cd /path/to/lxc_netbox

# Launch interactive menu (will prompt for Vault configuration)
./deploy.sh
```

The script will prompt for:

- Vault server address (VAULT_ADDR) if not set
- Vault username (VAULT_USERNAME) if not set
- Vault password during authentication

The interactive menu provides these options:

1. **Deploy Infrastructure** - Full deployment (Vault + Terraform + Ansible)
2. **Dry-Run / Plan** - Preview changes without applying
3. **Check Status** - View current deployment status
4. **Destroy Infrastructure** - Remove all resources
5. **Ansible Only** - Run configuration management only (requires VAULT_TOKEN)

### Command-Line Mode (For Automation)

```bash
# Full deployment
./deploy.sh deploy

# Dry-run (plan without applying)
./deploy.sh plan

# Check deployment status
./deploy.sh status

# Destroy infrastructure
./deploy.sh destroy

# Ansible only (requires VAULT_TOKEN)
export VAULT_TOKEN=$(vault print token)
./deploy.sh ansible
```

## 📖 Detailed Usage

### 1. Planning (Dry-Run)

Preview what will be created without applying changes:

```bash
./deploy.sh plan
```

This runs:

1. All pre-flight checks
2. Vault authentication and credential generation
3. Terraform initialization (with Transit encryption backend)
4. Terraform validation
5. Terraform plan (shows resources to be created)

**Note**: No infrastructure is created in this mode.

### 2. Full Deployment

Deploy complete infrastructure and configure NetBox:

```bash
./deploy.sh deploy
```

**Workflow:**

1. ✅ Pre-flight checks (binaries, files, SSH keys)
2. ✅ Vault connectivity and authentication
3. ✅ Vault secrets validation
4. ✅ Terraform initialization (S3 backend with Transit encryption)
5. ✅ Terraform validation
6. ✅ Terraform apply (creates LXC container)
7. ⏳ Wait for container to boot (30 seconds)
8. ✅ Generate Ansible inventory from Terraform outputs
9. ✅ Test Ansible connectivity (retries up to 3 times)
10. ✅ Run Ansible playbook:
    - Install PostgreSQL 17
    - Install Redis 7
    - Install NetBox from GitHub
    - Configure Gunicorn
    - Set up systemd services (netbox, netbox-rq)
    - Configure Nginx reverse proxy
    - Create Django superuser
11. ✅ Verify all services are running
12. ✅ Display deployment summary

**Duration**: Typically 8-15 minutes depending on network speed and package downloads.

### 3. Checking Status

View information about deployed infrastructure:

```bash
./deploy.sh status
```

This shows:

- Vault connection status
- Terraform state information
- Container IP address
- NetBox URL
- SSH command
- Service status (PostgreSQL, Redis, NetBox, Nginx)
- Ansible connectivity status

### 4. Destroying Infrastructure

Remove all deployed resources:

```bash
./deploy.sh destroy
```

**Safety Features:**

- Initial confirmation prompt
- Requires typing "destroy" to confirm
- Lists what will be removed
- Option to remove generated files
- **Note**: Vault secrets are NOT removed automatically

**Warning**: This is destructive and cannot be undone!

### 5. Ansible-Only Workflow

Run only Ansible without Terraform:

```bash
# Set VAULT_TOKEN first (required for Ansible to access Vault)
export VAULT_TOKEN=$(vault print token)
./deploy.sh ansible
```

**Note**: VAULT_TOKEN is passed via environment variable (secure, not shown in logs).

Use this when:

- Infrastructure is already deployed
- Re-running configuration management
- Testing Ansible playbook changes
- Recovering from partial deployment
- Updating NetBox configuration

### 6. Manual Deployment (Alternative to Automated Script)

For advanced users who prefer manual control or need to debug individual steps:

#### Step 1: Set Vault Environment

```bash
# Set your Vault server address
export VAULT_ADDR="https://vault.example.com:8200"

# Set your Vault username
export VAULT_USERNAME="your_username"
```

#### Step 2: Authenticate with Vault

```bash
vault login -method=userpass username="${VAULT_USERNAME}"
```

#### Step 3: Generate AWS Credentials

```bash
vault read -format=json aws/proxmox/creds/tofu_state_backup | tee /tmp/aws_creds.json
export AWS_ACCESS_KEY_ID=$(jq -r '.data.access_key' /tmp/aws_creds.json)
export AWS_SECRET_ACCESS_KEY=$(jq -r '.data.secret_key' /tmp/aws_creds.json)
export VAULT_TOKEN=$(vault token lookup -format=json | jq -r '.data.id')
rm -f /tmp/aws_creds.json
```

#### Step 4: Set OpenTofu Provider Password

```bash
export TF_VAR_vault_password="your_vault_password"
```

#### Step 5: Initialize and Apply Terraform

```bash
cd terraform
tofu init -backend-config=s3.backend.config
tofu validate
tofu plan
tofu apply
```

#### Step 6: Create Ansible Inventory

```bash
# Get container IP from Terraform
CONTAINER_IP=$(tofu output -raw lxc_ip_address | cut -d'/' -f1)

# Create inventory
cat > ../ansible/inventory.yml << EOF
all:
  children:
    netbox:
      hosts:
        netbox-server:
          ansible_host: ${CONTAINER_IP}
          ansible_port: 22
          ansible_user: ansible
          ansible_ssh_private_key_file: ~/.ssh/ansible
          ansible_python_interpreter: /usr/bin/python3
      vars:
        ansible_become: true
        ansible_become_method: sudo
EOF
```

#### Step 7: Run Ansible

```bash
cd ../ansible
export VAULT_TOKEN=$(vault print token)
ansible-playbook -i inventory.yml site.yml
```

**Note**: VAULT_TOKEN must be set for Ansible to access Vault secrets.

## ⚙️ Configuration

### Required Vault Secrets

The deploy.sh script verifies these secrets in Vault:

| Secret Path | Keys | Purpose |
| ------------- | ------ | --------- |
| `secrets/proxmox/credentials` | `endpoint`, `node`, `password` | Proxmox API access |
| `secrets/netbox/config` | `secret_key` | Django SECRET_KEY |
| `secrets/netbox/config` | `superuser_password` | Admin user password |

Verify secrets exist:

```bash
# Authenticate with Vault
vault login -method=userpass username=your_username

# Check secrets
vault kv get secrets/proxmox/credentials
vault kv get secrets/netbox/config
```

### S3 Backend Configuration

#### Using S3 Remote State with Transit Encryption (Recommended)

Edit `terraform/s3.backend.config`:

```hcl
bucket = "your-terraform-state-bucket"
key    = "netbox/terraform.tfstate"
profile = "your-aws-profile"
shared_credentials_files = ["/home/username/.aws/credentials"]

# Transit encryption is configured in backend.tf
encrypt = true
```

The script will automatically:

- Detect S3 backend configuration
- Authenticate with Vault
- Use Transit engine for state encryption

#### Using Local State (Not Recommended)

If `s3.backend.config` is not found:

- Script will warn about local state usage
- State will be stored in `terraform/terraform.tfstate`
- **Warning**: Local state is not recommended for production

### Logging Configuration

Logs are automatically created:

```bash
# Log location
logs/deployment_YYYYMMDD_HHMMSS.log

# View logs
tail -f logs/deployment_20260115_093000.log

# Search for errors
grep ERROR logs/*.log

# View only warnings and errors
grep -E "ERROR|WARNING" logs/*.log
```

See [logs/README.md](logs/README.md) for log management details.

## 🔧 Troubleshooting

### Common Issues

#### 1. Vault Connection Fails

**Error**: `Vault server is not reachable`

**Solution**:

```bash
# Check Vault server status
vault status

# Verify VAULT_ADDR
echo $VAULT_ADDR

# Test connectivity
curl -k $VAULT_ADDR/v1/sys/health

# Check vault_init.sh
cat terraform/vault_init.sh
source terraform/vault_init.sh
```

#### 2. Vault Authentication Fails

**Error**: `Vault authentication test failed`

**Solution**:

```bash
# Re-authenticate
source terraform/vault_init.sh

# Check token validity
vault token lookup

# Renew token if needed
vault token renew

# For userpass, re-login
vault login -method=userpass username=netbox-automation
```

#### 3. Required Vault Secrets Missing

**Error**: `Required Vault secret 'secrets/proxmox/credentials' not found`

**Solution**:

```bash
# Create missing secrets
vault kv put secrets/proxmox/credentials \
  endpoint="https://192.0.2.100:8006" \
  node="pve" \
  password="your-password"

vault kv put secrets/netbox/config \
  secret_key="$(openssl rand -base64 64 | tr -d '\n')" \
  superuser_password="$(openssl rand -base64 32)"
```

#### 4. Transit Engine Not Available

**Error**: `Vault Transit encryption engine not available`

**Solution**:

```bash
# Enable Transit engine
vault secrets enable transit

# Create encryption key
vault write -f transit/keys/netbox

# Verify
vault read transit/keys/netbox
```

#### 5. PostgreSQL Service Fails to Start

**Error**: `PostgreSQL is not running on netbox host`

**Solution**:

```bash
# SSH to container
ssh -i ~/.ssh/ansible ansible@<container-ip>

# Check PostgreSQL status
sudo systemctl status postgresql

# View logs
sudo journalctl -u postgresql -n 50

# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-17-main.log

# Restart if needed
sudo systemctl restart postgresql
```

#### 6. Redis Connection Issues

**Error**: `Redis is not running`

**Solution**:

```bash
# Check Redis status
sudo systemctl status redis-server

# Test Redis connectivity
redis-cli ping

# View logs
sudo journalctl -u redis-server -n 50

# Restart if needed
sudo systemctl restart redis-server
```

#### 7. NetBox Service Fails

**Error**: `NetBox is not running`

**Solution**:

```bash
# Check both NetBox services
sudo systemctl status netbox
sudo systemctl status netbox-rq

# View logs
sudo journalctl -u netbox -n 50
sudo journalctl -u netbox-rq -n 50

# Check NetBox application logs
sudo tail -f /opt/netbox/logs/error.log
sudo tail -f /opt/netbox/logs/access.log

# Test NetBox directly
curl http://localhost:8001

# Restart services
sudo systemctl restart netbox netbox-rq
```

#### 8. Nginx Configuration Issues

**Error**: `Nginx is not serving NetBox correctly`

**Solution**:

```bash
# Check Nginx status
sudo systemctl status nginx

# Test configuration
sudo nginx -t

# View error logs
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/netbox.access.log

# Check which port is being used
sudo netstat -tlnp | grep nginx

# Restart Nginx
sudo systemctl restart nginx
```

#### 9. Ansible Connectivity Fails

**Error**: `Ansible connectivity test failed after 3 retries`

**Possible Causes**:

- Container not fully booted (wait longer)
- SSH key not configured correctly
- Wrong IP address in inventory
- Firewall blocking SSH

**Solution**:

```bash
# Check container status in Proxmox
pvesh get /nodes/pve/lxc/201/status/current

# Test SSH manually
ssh -i ~/.ssh/ansible ansible@<container-ip>

# Regenerate inventory
cd ansible
cat > inventory.yml << 'EOF'
all:
  children:
    netbox:
      hosts:
        netbox-server:
          ansible_host: YOUR_CONTAINER_IP
          ansible_port: 22
          ansible_user: ansible
          ansible_ssh_private_key_file: ~/.ssh/ansible
          ansible_python_interpreter: /usr/bin/python3
      vars:
        ansible_become: true
        ansible_become_method: sudo
EOF

# Test connectivity
ansible netbox -m ping

# Re-run Ansible
./deploy.sh ansible
```

#### 10. Permission Denied on deploy.sh

**Error**: `Permission denied: ./deploy.sh`

**Solution**:

```bash
chmod +x deploy.sh
./deploy.sh
```

### Multi-Service Verification

Check all services are working together:

```bash
# On the container
ssh -i ~/.ssh/ansible ansible@<container-ip>

# Check all services
sudo systemctl status postgresql redis-server netbox netbox-rq nginx

# Test database connection
sudo -u postgres psql -c '\l'

# Test Redis
redis-cli ping

# Test NetBox application
curl http://localhost:8001

# Test Nginx proxy
curl http://localhost

# Check NetBox web interface
curl -I http://<container-ip>
```

### Error Recovery

#### Partial Terraform Deployment

If Terraform fails mid-deployment:

```bash
# Check what was created
./deploy.sh status

# Try to apply again (Terraform is idempotent)
cd terraform
# Authenticate with Vault
vault login -method=userpass username=your_username
export VAULT_TOKEN=$(vault token lookup -format=json | jq -r '.data.id')
tofu apply

# Or destroy and start over
./deploy.sh destroy
./deploy.sh deploy
```

#### Ansible Fails After Terraform Succeeds

Infrastructure is deployed but not configured:

```bash
# Check Ansible inventory
cat ansible/inventory.yml

# Test connectivity
cd ansible
ansible netbox -m ping

# Re-run specific roles
ansible-playbook site.yml --tags postgresql
ansible-playbook site.yml --tags redis
ansible-playbook site.yml --tags netbox

# Or full playbook
ansible-playbook site.yml

# Or use the script
./deploy.sh ansible
```

### Debug Mode

For more verbose output:

```bash
# Terraform debug
cd terraform
source vault_init.sh
TF_LOG=DEBUG tofu apply

# Ansible verbose mode
cd ansible
ansible-playbook site.yml -vvv

# Check individual role
ansible-playbook site.yml --tags netbox -vvv
```

## 🎓 Advanced Topics

### Running in CI/CD Pipeline

The script is designed to work in automated environments:

```yaml
# Example GitLab CI
deploy_netbox:
  before_script:
    # Vault authentication
    - export VAULT_ADDR="https://vault.example.com:8200"
    - export VAULT_TOKEN="${CI_VAULT_TOKEN}"
    
  script:
    # Run non-interactive deployment
    - ./deploy.sh deploy
    
  only:
    - main
```

### Custom Vault Policies

For tighter security, create minimal policies:

```hcl
# Read-only Proxmox credentials
path "secrets/data/proxmox/credentials" {
  capabilities = ["read"]
}

# Full access to NetBox secrets
path "secrets/data/netbox/*" {
  capabilities = ["create", "read", "update", "list"]
}

# Transit encryption only
path "transit/encrypt/netbox" {
  capabilities = ["update"]
}

path "transit/decrypt/netbox" {
  capabilities = ["update"]
}
```

### Multiple Environments

Deploy to different environments:

```bash
# Create environment-specific configs
cp terraform/vault_init.sh terraform/vault_init_prod.sh
cp terraform/vault_init.sh terraform/vault_init_dev.sh

# Use different secret paths
# In vault_init_prod.sh: export ENV="prod"
# In vault_init_dev.sh: export ENV="dev"

# Deploy with specific environment
source terraform/vault_init_prod.sh
./deploy.sh deploy
```

### Backup and Restore

#### NetBox Database Backup

```bash
# SSH to container
ssh -i ~/.ssh/ansible ansible@<container-ip>

# Backup PostgreSQL database
sudo -u postgres pg_dump netbox > /tmp/netbox_backup_$(date +%Y%m%d).sql

# Copy backup locally
scp -i ~/.ssh/ansible ansible@<container-ip>:/tmp/netbox_backup_*.sql ./backups/

# Store in Vault (encrypted)
vault kv put secrets/netbox/backups/$(date +%Y%m%d) \
  data=@./backups/netbox_backup_*.sql
```

#### Restore Database

```bash
# Retrieve from Vault
vault kv get -field=data secrets/netbox/backups/20260115 > restore.sql

# Copy to container
scp -i ~/.ssh/ansible restore.sql ansible@<container-ip>:/tmp/

# SSH and restore
ssh -i ~/.ssh/ansible ansible@<container-ip>
sudo -u postgres psql netbox < /tmp/restore.sql
sudo systemctl restart netbox netbox-rq
```

### Security Hardening

For production deployments:

1. **Use separate Vault namespace**:

   ```bash
   export VAULT_NAMESPACE="production/netbox"
   ```

2. **Implement least-privilege policies**:

   ```bash
   # Create separate policies for Terraform and Ansible
   vault policy write netbox-terraform policy-terraform.hcl
   vault policy write netbox-ansible policy-ansible.hcl
   ```

3. **Rotate Vault tokens regularly**:

   ```bash
   # Set token TTL
   vault token create -policy=netbox-deploy -ttl=1h
   ```

4. **Enable audit logging**:

   ```bash
   vault audit enable file file_path=/var/log/vault_audit.log
   ```

5. **Use AppRole for automation**:

   ```bash
   vault auth enable approle
   vault write auth/approle/role/netbox-deploy \
     token_policies="netbox-deploy" \
     token_ttl=1h \
     token_max_ttl=4h
   ```

## 📚 Additional Resources

- **Main README**: [../README.md](README.md)
- **Workspace README**: [../README.md](../README.md) - Deployment order
- **Vault Project**: [../lxc_vault/README.md](../lxc_vault/README.md) - Must deploy first!
- **Terraform Documentation**: [terraform/README.md](terraform/README.md)
- **Ansible Documentation**: [ansible/README.md](ansible/README.md)
- **Vault Policy Example**: [vault_policy.hcl.example](vault_policy.hcl.example)
- **Quick Reference**: [QUICKREF.sh](QUICKREF.sh)
- **Proxmox LXC Containers**: [https://pve.proxmox.com/wiki/Linux_Container](https://pve.proxmox.com/wiki/Linux_Container)
- **NetBox Documentation**: [https://docs.netbox.dev/](https://docs.netbox.dev/)
- **Vault Documentation**: [https://www.vaultproject.io/docs](https://www.vaultproject.io/docs)

## 🆘 Getting Help

If you encounter issues:

1. **Check logs**: `cat logs/deployment_*.log`
2. **Run pre-flight checks**: `./deploy.sh checks`
3. **Verify Vault connectivity**: `vault status && vault login`
4. **Check deployment status**: `./deploy.sh status`
5. **Review service logs**: See troubleshooting section above
6. **Check Proxmox logs**: `/var/log/pveproxy/access.log`

## 📝 Script Maintenance

The deployment script is located at: `deploy.sh`

To update:

```bash
# Make changes
vim deploy.sh

# Test in dry-run mode
./deploy.sh plan

# Test full deployment in dev environment
./deploy.sh deploy
```

**Important**: Always test changes in a development environment before production!
