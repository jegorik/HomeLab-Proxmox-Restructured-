# Automated Deployment Guide

This guide covers the automated deployment script (`deploy.sh`) for the HashiCorp Vault LXC Container project.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

## 🔍 Overview

The `deploy.sh` script is a professional-grade bash automation tool that handles the complete lifecycle of your Vault infrastructure deployment on Proxmox. It combines pre-flight validation, interactive prompts, Terraform/OpenTofu provisioning, and Ansible configuration management into a single, user-friendly interface.

### Key Benefits

- ✅ **Zero Manual Steps**: Fully automated deployment from start to finish
- ✅ **Intelligent Validation**: Comprehensive pre-flight checks catch issues early
- ✅ **Interactive & Scriptable**: Works both interactively and in CI/CD pipelines
- ✅ **Safe Operations**: Multiple confirmation prompts for destructive actions
- ✅ **Detailed Logging**: Every action is logged with timestamps
- ✅ **Error Recovery**: Clear instructions when things go wrong

## 📦 Prerequisites

### Required Software

The script will check for these during pre-flight validation:

| Software | Purpose | Installation |
|----------|---------|-------------|
| **OpenTofu** or **Terraform** | Infrastructure provisioning | `brew install opentofu` or download from [opentofu.org](https://opentofu.org) |
| **Ansible** | Configuration management | `pip install ansible` |
| **SSH Client** | Remote access | Pre-installed on most systems |
| **Git** | Version control | `sudo apt install git` |
| **jq** | JSON processing | `sudo apt install jq` |
| **AWS CLI** | S3 backend (optional) | `pip install awscli` |

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
ssh-keygen -t ed25519 -C "vault-lxc-root" -f ~/.ssh/pve_ssh

# For Ansible automation
ssh-keygen -t ed25519 -C "ansible@vault" -f ~/.ssh/ansible
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
   vim s3.backend.config  # Add AWS credentials
   ```

3. **State Encryption Passphrase**:
   ```bash
   openssl rand -base64 32 > ~/.ssh/state_passphrase
   chmod 600 ~/.ssh/state_passphrase
   ```

## 🚀 Quick Start

### Interactive Mode (Recommended for First-Time Users)

```bash
# Navigate to project directory
cd /path/to/lxc_vault

# Launch interactive menu
./deploy.sh
```

The interactive menu provides these options:
1. **Deploy Infrastructure** - Full deployment (Terraform + Ansible)
2. **Dry-Run / Plan** - Preview changes without applying
3. **Check Status** - View current deployment status
4. **Destroy Infrastructure** - Remove all resources
5. **Run Pre-flight Checks Only** - Validate environment
6. **Run Terraform Only** - Infrastructure provisioning only
7. **Run Ansible Only** - Configuration management only

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
```

## 📖 Detailed Usage

### 1. Pre-flight Checks

Run validation without making any changes:

```bash
./deploy.sh checks
```

This will verify:
- Required binaries are installed
- Project structure is correct
- Configuration files exist
- SSH keys are available
- State encryption is configured
- .gitignore is properly set up
- Environment variables are set

### 2. Planning (Dry-Run)

Preview what will be created without applying changes:

```bash
./deploy.sh plan
```

This runs:
1. All pre-flight checks
2. Terraform initialization
3. Terraform validation
4. Terraform plan (shows resources to be created)

**Note**: No infrastructure is created in this mode.

### 3. Full Deployment

Deploy complete infrastructure and configure Vault:

```bash
./deploy.sh deploy
```

**Workflow:**
1. ✅ Pre-flight checks (binaries, files, SSH keys)
2. ✅ Environment variable validation (prompts for missing values)
3. ✅ Terraform initialization (S3 backend or local state)
4. ✅ Terraform validation
5. ✅ Terraform apply (creates LXC container)
6. ⏳ Wait for container to boot (30 seconds)
7. ✅ Generate Ansible inventory from Terraform outputs
8. ✅ Test Ansible connectivity (retries up to 3 times)
9. ✅ Run Ansible playbook (install and configure Vault)
10. ✅ Display deployment summary

**Duration**: Typically 5-10 minutes depending on network speed.

### 4. Checking Status

View information about deployed infrastructure:

```bash
./deploy.sh status
```

This shows:
- Terraform state information
- Container IP address
- Vault URL
- SSH command
- Vault accessibility status
- Ansible connectivity status

### 5. Destroying Infrastructure

Remove all deployed resources:

```bash
./deploy.sh destroy
```

**Safety Features:**
- Initial confirmation prompt
- Requires typing "destroy" to confirm
- Lists what will be removed
- Option to remove generated files

**Warning**: This is destructive and cannot be undone!

### 6. Terraform-Only Workflow

Run only Terraform without Ansible:

```bash
./deploy.sh terraform
```

Use this when:
- You want to provision infrastructure manually configure later
- Testing Terraform changes
- Debugging Terraform issues

### 7. Ansible-Only Workflow

Run only Ansible without Terraform:

```bash
./deploy.sh ansible
```

Use this when:
- Infrastructure is already deployed
- Re-running configuration management
- Testing Ansible playbook changes
- Recovering from partial deployment

## ⚙️ Configuration

### Environment Variables

The script supports multiple methods for providing credentials:

#### Method 1: File-Based Credentials (Recommended)

```bash
# Create password file
echo "your-proxmox-password" > ~/.ssh/pve_root_password
chmod 600 ~/.ssh/pve_root_password

# Script will auto-detect this file
./deploy.sh deploy
```

#### Method 2: Environment Variables

```bash
# Set environment variables
export TF_VAR_pve_root_password="your-password"
export TF_VAR_proxmox_endpoint="https://192.168.1.100:8006"
export TF_VAR_proxmox_node="pve"

# Run deployment
./deploy.sh deploy
```

#### Method 3: Interactive Prompts

If credentials are not found, the script will prompt:

```bash
./deploy.sh deploy
# Will prompt: "Enter Proxmox root@pam password:"
```

### Credential Priority Order

1. **Environment variables** (`TF_VAR_*`) - Highest priority
2. **File-based credentials** (`~/.ssh/pve_root_password`)
3. **Interactive prompts** (if not found above)
4. **terraform.tfvars** file (for non-sensitive values)

### Required Variables

| Variable | File Location | Environment Variable | Required |
|----------|---------------|---------------------|----------|
| Proxmox password | `~/.ssh/pve_root_password` | `TF_VAR_pve_root_password` | ✅ Yes |
| Proxmox endpoint | `terraform.tfvars` | `TF_VAR_proxmox_endpoint` | Optional* |
| State passphrase | `~/.ssh/state_passphrase` | `TF_VAR_passphrase` | Optional** |

\* Can be set in terraform.tfvars  
\** Only needed for OpenTofu 1.8+ state encryption

### S3 Backend Configuration

#### Using S3 Remote State (Recommended)

Edit `terraform/s3.backend.config`:

```hcl
bucket = "your-terraform-state-bucket"
key    = "vault/terraform.tfstate"
profile = "your-aws-profile"
shared_credentials_files = ["/home/username/.aws/credentials"]
```

The script will automatically detect and use S3 backend.

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
tail -f logs/deployment_20260114_131600.log

# Search for errors
grep ERROR logs/*.log

# View only warnings and errors
grep -E "ERROR|WARNING" logs/*.log
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Binary Not Found

**Error**: `Missing required command: tofu`

**Solution**:
```bash
# Install OpenTofu
wget https://github.com/opentofu/opentofu/releases/download/v1.8.0/tofu_1.8.0_linux_amd64.zip
unzip tofu_1.8.0_linux_amd64.zip
sudo mv tofu /usr/local/bin/
```

#### 2. Terraform Initialization Fails

**Error**: `Terraform initialization failed`

**Solution**:
```bash
# Check AWS credentials (if using S3 backend)
aws sts get-caller-identity

# Or use local state temporarily
mv terraform/s3.backend.config terraform/s3.backend.config.disabled
./deploy.sh plan
```

#### 3. Ansible Connectivity Fails

**Error**: `Ansible connectivity test failed after 3 retries`

**Possible Causes**:
- Container not fully booted (wait longer)
- SSH key not configured correctly
- Wrong IP address in inventory
- Firewall blocking SSH

**Solution**:
```bash
# Check container status in Proxmox
pvesh get /nodes/pve/lxc/200/status/current

# Test SSH manually
ssh -i ~/.ssh/ansible ansible@<container-ip>

# Re-run Ansible only
./deploy.sh ansible
```

#### 4. Inventory Creation Fails - "Could not get container IP"

**Error**: `Could not get container IP from Terraform outputs`

**Cause**: The script expects the Terraform output `lxc_ip_address` or `vault_ip_address`.

**Solution**:
```bash
# Verify Terraform outputs exist
cd terraform
tofu output

# Check the IP output specifically
tofu output lxc_ip_address

# If the output exists but script still fails, manually create inventory:
cd ../ansible
cat > inventory.yml << 'EOF'
all:
  children:
    vault:
      hosts:
        vault-server:
          ansible_host: YOUR_CONTAINER_IP  # Without /24
          ansible_port: 22
          ansible_user: ansible
          ansible_ssh_private_key_file: ~/.ssh/ansible
          ansible_python_interpreter: /usr/bin/python3
      vars:
        ansible_become: true
        ansible_become_method: sudo
EOF

# Then run Ansible
ansible vault -m ping
ansible-playbook site.yml
```

**Note**: The script automatically strips CIDR notation (e.g., `/24`) from IP addresses.

#### 5. Permission Denied on deploy.sh

**Error**: `Permission denied: ./deploy.sh`

**Solution**:
```bash
chmod +x deploy.sh
./deploy.sh
```

#### 5. Missing terraform.tfvars

**Error**: `terraform.tfvars not found`

**Solution**:
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Edit with your values
```

Or use environment variables:
```bash
export TF_VAR_proxmox_endpoint="https://192.168.1.100:8006"
export TF_VAR_pve_root_password="your-password"
export TF_VAR_proxmox_node="pve"
./deploy.sh deploy
```

#### 6. State Encryption Passphrase Missing

**Error**: `State encryption passphrase file not found`

**Solution**:
```bash
# Generate new passphrase
openssl rand -base64 32 > ~/.ssh/state_passphrase
chmod 600 ~/.ssh/state_passphrase

# Or proceed without encryption (OpenTofu 1.8+ feature only)
# Script will continue with warning
```

### Error Recovery

#### Partial Terraform Deployment

If Terraform fails mid-deployment:

```bash
# Check what was created
./deploy.sh status

# Try to apply again (Terraform is idempotent)
cd terraform
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
ansible vault -m ping

# Re-run playbook
ansible-playbook site.yml

# Or use the script
./deploy.sh ansible
```

#### Network Connectivity Issues

```bash
# Verify container is running
pvesh get /nodes/pve/lxc/200/status/current

# Check container IP
pvesh get /nodes/pve/lxc/200/config | grep net0

# Test network from Proxmox host
ping <container-ip>

# Check firewall rules
iptables -L -n | grep <container-ip>
```

### Debug Mode

For more verbose output, you can modify the script temporarily:

```bash
# Edit deploy.sh
set -x  # Add this near the top for bash debug mode

# Or run specific Terraform/Ansible commands manually
cd terraform
tofu plan -out=tfplan
tofu apply tfplan

cd ../ansible
ansible-playbook site.yml -vvv  # Triple verbose
```

## 🎓 Advanced Topics

### Running in CI/CD Pipeline

The script is designed to work in automated environments:

```yaml
# Example GitLab CI
deploy_vault:
  script:
    # Set environment variables
    - export TF_VAR_pve_root_password="${PROXMOX_PASSWORD}"
    - export TF_VAR_proxmox_endpoint="${PROXMOX_ENDPOINT}"
    
    # Run non-interactive deployment
    - ./deploy.sh deploy
    
  only:
    - main
```

### Custom SSH Keys

If your SSH keys are in non-standard locations:

```bash
# Edit terraform.tfvars
ssh_public_key_path = "~/.ssh/custom_key.pub"
ssh_private_key_path = "~/.ssh/custom_key"
ansible_ssh_public_key_path = "~/.ssh/ansible_custom.pub"
```

### Multiple Environments

Deploy to different environments:

```bash
# Create environment-specific tfvars
cp terraform.tfvars terraform-prod.tfvars
cp terraform.tfvars terraform-dev.tfvars

# Edit each with environment-specific values
vim terraform-prod.tfvars
vim terraform-dev.tfvars

# Deploy with specific tfvars
cd terraform
tofu apply -var-file=terraform-prod.tfvars

# Or use workspaces
tofu workspace new prod
tofu workspace new dev
tofu workspace select prod
```

### Customizing the Script

Key functions you can modify:

```bash
# Change default paths
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"  # Line 27
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"      # Line 28

# Adjust wait times
sleep 30  # Wait for container boot (line 1308)

# Modify retry attempts
while [[ ${retry_count} -lt 3 ]]; do  # Line 1315

# Change log retention
# Add cleanup in main() function
find "${LOGS_DIR}" -name "*.log" -mtime +30 -delete
```

### Security Hardening

For production deployments:

1. **Use dedicated automation password**:
   ```bash
   # Don't use your interactive root password
   # Create separate automation password in Proxmox
   ```

2. **Restrict password file permissions**:
   ```bash
   chmod 400 ~/.ssh/pve_root_password
   chown root:root ~/.ssh/pve_root_password
   ```

3. **Use AWS Secrets Manager** for credentials:
   ```bash
   # Store in AWS Secrets Manager
   export TF_VAR_pve_root_password=$(aws secretsmanager get-secret-value \
     --secret-id proxmox/root-password --query SecretString --output text)
   ```

4. **Enable audit logging**:
   ```bash
   # The script logs everything to logs/ directory
   # Configure log shipping to SIEM
   ```

5. **Rotate credentials regularly**:
   ```bash
   # Update password every 90 days
   # Update script or add reminder:
   echo "Last password change: $(date)" > ~/.ssh/pve_password_date
   ```

## 📚 Additional Resources

- **Main README**: [../README.md](README.md)
- **Terraform Documentation**: [terraform/README.md](terraform/README.md)
- **Ansible Documentation**: [ansible/README.md](ansible/README.md)
- **Proxmox LXC Containers**: [https://pve.proxmox.com/wiki/Linux_Container](https://pve.proxmox.com/wiki/Linux_Container)
- **OpenTofu Documentation**: [https://opentofu.org/docs/](https://opentofu.org/docs/)
- **Ansible Documentation**: [https://docs.ansible.com/](https://docs.ansible.com/)

## 🆘 Getting Help

If you encounter issues:

1. **Check logs**: `cat logs/deployment_*.log`
2. **Run pre-flight checks**: `./deploy.sh checks`
3. **Verify configuration**: `./deploy.sh status`
4. **Review documentation**: See links above
5. **Check Proxmox logs**: `/var/log/pveproxy/access.log`

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

