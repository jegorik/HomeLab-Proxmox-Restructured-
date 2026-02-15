# Ansible Configuration - HashiCorp Vault Deployment

This directory contains Ansible playbooks and roles for automated installation and configuration of HashiCorp Vault on an LXC container.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Playbook Structure](#playbook-structure)
- [Roles](#roles)
- [Variables](#variables)
- [Execution](#execution)
- [Post-Deployment](#post-deployment)
- [Troubleshooting](#troubleshooting)

## 🔍 Overview

### What This Does

This Ansible configuration automates:

1. **System Preparation**: Updates packages and installs dependencies
2. **Vault Installation**: Adds HashiCorp repository and installs Vault
3. **Service Configuration**: Creates systemd service with security hardening
4. **Initialization**: Automatically initializes Vault and generates unseal keys
5. **Verification**: Confirms Vault is running and accessible

### Deployment Flow

```text
┌─────────────────┐
│  site.yml       │  Main playbook entry point
└────────┬────────┘
         │
         ├──→ ┌──────────────┐
         │    │  vault role  │  Install & configure Vault
         │    └──────────────┘
         │
         └──→ ┌───────────────┐
              │ systemd role  │  Service management & initialization
              └───────────────┘
```

## 📦 Prerequisites

### Software Requirements

| Tool | Version | Installation |
| ---- | ------- | ------------ |
| **Ansible** | 2.15+ | `pip install ansible` or `apt install ansible` |
| **Python** | 3.9+ | Pre-installed on most systems |
| **SSH Client** | Any | Pre-installed on most systems |

### Container Requirements

- ✅ LXC container deployed (via Terraform)
- ✅ Debian 12+ or Ubuntu 22.04+
- ✅ Ansible user created with sudo access
- ✅ SSH key authentication configured
- ✅ Internet connectivity for package installation

### Network Requirements

- Container must be reachable from Ansible control node
- Outbound access to `apt.releases.hashicorp.com`
- Outbound access to Debian/Ubuntu package repositories

## 🚀 Quick Start

### Step 1: Create Inventory

```bash
# Copy example inventory
cp inventory.yml.example inventory.yml

# Edit with your container IP
vim inventory.yml
```

**Example inventory.yml:**

```yaml
all:
  children:
    vault:
      hosts:
        vault-server:
          ansible_host: 203.0.113.50
          ansible_port: 22
          ansible_user: ansible
          ansible_ssh_private_key_file: ~/.ssh/ansible
          ansible_python_interpreter: /usr/bin/python3
      vars:
        ansible_become: true
        ansible_become_method: sudo
```

### Step 2: Test Connectivity

```bash
# Ping test
ansible vault -m ping

# Expected output:
# vault-server | SUCCESS => {
#     "changed": false,
#     "ping": "pong"
# }
```

### Step 3: Run Playbook

```bash
# Deploy Vault
ansible-playbook site.yml

# Or with verbose output
ansible-playbook site.yml -v

# Or with specific tags
ansible-playbook site.yml --tags vault
```

### Step 4: Retrieve Vault Keys

```bash
# SSH to container and get initialization keys
ssh ansible@<container-ip> sudo cat /root/vault-keys.txt

# Example output:
# Unseal Key 1: xxxxx...
# Unseal Key 2: xxxxx...
# Unseal Key 3: xxxxx...
# Unseal Key 4: xxxxx...
# Unseal Key 5: xxxxx...
# Initial Root Token: s.xxxxx...
```

**CRITICAL**: Save these keys in a secure password manager immediately!

## 📁 Playbook Structure

### File Organization

```text
ansible/
├── README.md                    # This file
├── ansible.cfg                  # Ansible configuration
├── site.yml                     # Main playbook
├── inventory.yml.example        # Inventory template
├── inventory.yml                # Your inventory (gitignored)
│
└── roles/                       # Ansible roles
    ├── vault/                   # Vault installation
    │   ├── README.md            # Role documentation
    │   ├── tasks/
    │   │   └── main.yml         # Installation tasks
    │   ├── templates/
    │   │   └── vault.hcl.j2     # Vault configuration template
    │   ├── handlers/
    │   │   └── main.yml         # Service restart handlers
    │   └── meta/
    │       └── main.yml         # Role metadata
    │
    └── systemd/                 # Service management
        ├── README.md            # Role documentation
        ├── tasks/
        │   └── main.yml         # Service tasks
        ├── templates/
        │   └── vault.service.j2 # Systemd unit template
        ├── handlers/
        │   └── main.yml         # Systemd handlers
        └── meta/
            └── main.yml         # Role metadata
```

### Main Playbook (site.yml)

```yaml
- name: Deploy HashiCorp Vault
  hosts: vault
  become: true
  gather_facts: true

  vars:
    vault_version: "v1.21.2"
    vault_ui_port: 8200
    # ... other variables

  roles:
    - role: vault
      tags: ['vault', 'security-storage']
    
    - role: systemd
      tags: ['systemd', 'services']

  post_tasks:
    - name: Display deployment summary
      # ... shows next steps
```

## 🎭 Roles

### 1. Vault Role (`roles/vault`)

**Purpose**: Installs and configures HashiCorp Vault

**Tasks**:

- Installs system dependencies (curl, gpg, wget)
- Adds HashiCorp GPG key and APT repository
- Installs Vault package
- Creates Vault system user and group
- Creates data and configuration directories
- Deploys Vault configuration file (`/etc/vault.d/vault.hcl`)

**Templates**:

- `vault.hcl.j2`: Vault server configuration

**Key Configuration**:

```hcl
ui = true                    # Enable Web UI
disable_mlock = true         # Required for LXC
storage "file" {             # File-based storage
  path = "/var/lib/vault/data"
}
listener "tcp" {             # HTTP listener (no TLS)
  address     = "0.0.0.0:8200"
  tls_disable = 1
}
```

See [roles/vault/README.md](roles/vault/README.md) for details.

### 2. Systemd Role (`roles/systemd`)

**Purpose**: Manages Vault systemd service and initialization

**Tasks**:

- Creates systemd service unit file
- Enables and starts Vault service
- Waits for Vault to be ready (port 8200)
- Checks if Vault is already initialized
- Initializes Vault if needed
- Saves unseal keys to `/root/vault-keys.txt`
- Sets proper file permissions (0600)

**Templates**:

- `vault.service.j2`: Systemd unit file with security hardening

**Security Hardening**:

```ini
ProtectSystem=full           # Read-only /usr, /boot, /efi
ProtectHome=read-only        # Read-only /home
PrivateTmp=yes              # Private /tmp
PrivateDevices=yes          # Limited device access
NoNewPrivileges=yes         # Prevent privilege escalation
```

See [roles/systemd/README.md](roles/systemd/README.md) for details.

## 📊 Variables

### Playbook Variables (site.yml)

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `vault_version` | `v1.21.2` | Vault version (for documentation) |
| `vault_ui_port` | `8200` | Web UI port |
| `vault_keyring_dir` | `/usr/share/keyrings` | GPG keyring directory |
| `vault_data_dir` | `/var/lib/vault/data` | Vault data storage path |
| `vault_config_dir` | `/etc/vault.d` | Configuration directory |
| `vault_config_file` | `vault.hcl.j2` | Config template name |
| `vault_config_path` | `/etc/vault.d/vault.hcl` | Config file path |
| `vault_service_file` | `vault.service.j2` | Service template name |
| `vault_service_path` | `/etc/systemd/system/vault.service` | Service unit path |
| `vault_user` | `vault` | System user for Vault |
| `vault_group` | `vault` | System group for Vault |

### Overriding Variables

#### Method 1: Edit site.yml

```yaml
vars:
  vault_version: "v1.22.0"  # Use different version
  vault_ui_port: 8300       # Use different port
```

#### Method 2: Extra Variables (Command Line)

```bash
ansible-playbook site.yml -e "vault_ui_port=8300"
```

#### Method 3: Group Variables

```bash
# Create group_vars directory
mkdir -p group_vars

# Create vault group variables
cat > group_vars/vault.yml <<EOF
---
vault_ui_port: 8300
vault_data_dir: /mnt/vault-data
EOF
```

#### Method 4: Host Variables

```yaml
# In inventory.yml
vault:
  hosts:
    vault-server:
      ansible_host: 203.0.113.50
      vault_ui_port: 8300  # Host-specific override
```

## ▶️ Execution

### Basic Execution

```bash
# Run entire playbook
ansible-playbook site.yml

# Check mode (dry-run, no changes)
ansible-playbook site.yml --check

# Diff mode (show file changes)
ansible-playbook site.yml --check --diff
```

### Tag-Based Execution

```bash
# Run only vault installation
ansible-playbook site.yml --tags vault

# Run only systemd configuration
ansible-playbook site.yml --tags systemd

# Skip specific tags
ansible-playbook site.yml --skip-tags initialize

# List available tags
ansible-playbook site.yml --list-tags
```

### Verbose Output

```bash
# Level 1: Basic info
ansible-playbook site.yml -v

# Level 2: Task input/output
ansible-playbook site.yml -vv

# Level 3: Includes task execution details
ansible-playbook site.yml -vvv

# Level 4: Connection debugging
ansible-playbook site.yml -vvvv
```

### Limiting Execution

```bash
# Run on specific host
ansible-playbook site.yml --limit vault-server

# Run on specific group
ansible-playbook site.yml --limit vault

# Use patterns
ansible-playbook site.yml --limit "vault*"
```

### Step-by-Step Execution

```bash
# Prompt before each task
ansible-playbook site.yml --step

# Start at specific task
ansible-playbook site.yml --start-at-task="Install Vault"
```

## 📤 Post-Deployment

### Verify Installation

```bash
# Check Vault service status
ansible vault -a "systemctl status vault" -b

# Check Vault version
ansible vault -a "vault version"

# Check Vault status
ansible vault -a "VAULT_ADDR='http://127.0.0.1:8200' vault status"
```

### Retrieve Vault Keys

```bash
# Method 1: SSH directly
ssh ansible@<container-ip> sudo cat /root/vault-keys.txt

# Method 2: Ansible ad-hoc command
ansible vault -a "cat /root/vault-keys.txt" -b

# Method 3: Copy to local machine
ansible vault -m fetch \
  -a "src=/root/vault-keys.txt dest=./vault-keys-backup.txt flat=yes" -b
```

**Save Output**:

```text
Unseal Key 1: <key1>
Unseal Key 2: <key2>
Unseal Key 3: <key3>
Unseal Key 4: <key4>
Unseal Key 5: <key5>

Initial Root Token: <token>
```

**IMPORTANT**:

1. Save these keys in a secure password manager (1Password, Bitwarden, etc.)
2. Store keys and token separately for security
3. Delete `/root/vault-keys.txt` after saving:

   ```bash
   ssh ansible@<container-ip> sudo rm /root/vault-keys.txt
   ```

### Access Vault UI

```bash
# Get container IP from inventory
ansible vault -m debug -a "var=ansible_host"

# Open in browser
# URL: http://<container-ip>:8200

# Login with Initial Root Token
```

### Initialize Vault CLI

```bash
# On your local machine
export VAULT_ADDR='http://<container-ip>:8200'
export VAULT_TOKEN='<root-token>'

# Test connection
vault status

# Enable audit logging (recommended)
vault audit enable file file_path=/var/log/vault/audit.log

# Create admin policy
vault policy write admin-policy -<<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
```

## 🔧 Troubleshooting

### Connectivity Issues

#### Cannot Connect to Host

```bash
# Test SSH connection manually
ssh ansible@<container-ip>

# Test with Ansible
ansible vault -m ping

# Check SSH key permissions
chmod 600 ~/.ssh/ansible

# Verify inventory configuration
cat inventory.yml
```

#### Connection Timeout

```bash
# Check if container is running
ssh root@proxmox-host pct list | grep vault

# Check container network
ssh root@proxmox-host pct exec <vmid> -- ip addr

# Test from Proxmox host
ssh root@proxmox-host ping -c 3 <container-ip>
```

### Installation Issues

#### Package Installation Fails

```bash
# SSH to container
ssh ansible@<container-ip>

# Check internet connectivity
curl -I https://apt.releases.hashicorp.com

# Check DNS resolution
nslookup apt.releases.hashicorp.com

# Update package lists manually
sudo apt update

# Check disk space
df -h
```

#### HashiCorp Repository Issues

```bash
# SSH to container
ssh ansible@<container-ip>

# Check GPG key
ls -la /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Check repository configuration
cat /etc/apt/sources.list.d/hashicorp.list

# Manually add repository
wget -qO- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
```

### Service Issues

#### Vault Service Won't Start

```bash
# SSH to container
ssh ansible@<container-ip>

# Check service status
sudo systemctl status vault

# View recent logs
sudo journalctl -u vault -n 50

# Test configuration
sudo vault server -config=/etc/vault.d/vault.hcl -test

# Check file permissions
sudo ls -la /etc/vault.d/
sudo ls -la /var/lib/vault/
```

#### Vault Port Not Listening

```bash
# SSH to container
ssh ansible@<container-ip>

# Check if port is open
sudo ss -tlnp | grep 8200

# Check Vault process
ps aux | grep vault

# Test local connectivity
curl http://127.0.0.1:8200/v1/sys/health
```

### Initialization Issues

#### Vault Already Initialized

This is normal if re-running playbook. The playbook checks initialization status and skips if already done.

```bash
# Check Vault status
ssh ansible@<container-ip>
export VAULT_ADDR='http://127.0.0.1:8200'
vault status | grep Initialized
```

#### Keys File Not Created

```bash
# Check if file exists
ssh ansible@<container-ip> sudo ls -la /root/vault-keys.txt

# If missing, manually initialize
ssh ansible@<container-ip>
export VAULT_ADDR='http://127.0.0.1:8200'
vault operator init > /tmp/vault-keys.txt
sudo mv /tmp/vault-keys.txt /root/
sudo chmod 600 /root/vault-keys.txt
```

### Playbook Failures

#### Syntax Errors

```bash
# Check playbook syntax
ansible-playbook site.yml --syntax-check

# Lint playbook (install ansible-lint first)
ansible-lint site.yml
```

#### Task Hangs

```bash
# Check timeout settings in ansible.cfg
cat ansible.cfg | grep timeout

# Increase timeouts if needed
vim ansible.cfg
# timeout = 60
# gather_timeout = 60
```

#### Permission Denied

```bash
# Verify ansible user has sudo
ssh ansible@<container-ip> sudo -l

# Check sudoers configuration
ssh ansible@<container-ip> sudo cat /etc/sudoers.d/ansible

# Verify become settings in inventory
grep become inventory.yml
```

### Debug Mode

```bash
# Enable Ansible debug output
ANSIBLE_DEBUG=1 ansible-playbook site.yml -vvvv

# Enable Vault debug logging
ssh ansible@<container-ip>
sudo systemctl edit vault
# Add: Environment="VAULT_LOG_LEVEL=debug"
sudo systemctl daemon-reload
sudo systemctl restart vault
sudo journalctl -u vault -f
```

## 🔒 Security Best Practices

### Vault Keys Management

1. **Immediate Actions After Deployment**:
   - ✅ Save unseal keys and root token to password manager
   - ✅ Store keys and token separately
   - ✅ Delete `/root/vault-keys.txt` from container
   - ✅ Rotate root token after creating admin users

2. **Key Distribution**:
   - Distribute unseal keys to different trusted individuals
   - Require 3 of 5 keys to unseal (default)
   - Never store all keys in one location

3. **Token Management**:
   - Don't use root token for day-to-day operations
   - Create role-based tokens with limited policies
   - Set token TTLs appropriately
   - Rotate tokens regularly

### Ansible Security

1. **Inventory Protection**:
   - Keep `inventory.yml` in `.gitignore`
   - Use Ansible Vault for sensitive variables
   - Store inventory in secure location

2. **SSH Key Protection**:
   - Use separate SSH keys for Ansible
   - Set proper permissions (600 for private keys)
   - Use SSH agent for key management
   - Rotate keys periodically

3. **Playbook Security**:
   - Use `no_log: true` for sensitive tasks
   - Don't hardcode passwords in playbooks
   - Use Ansible Vault for secrets
   - Review playbooks before execution

### Container Security

1. **Update Regularly**:

   ```bash
   ansible vault -m apt -a "upgrade=safe update_cache=yes" -b
   ```

2. **Configure Firewall**:

   ```bash
   # Example: Allow only specific IPs to Vault port
   ansible vault -m apt -a "name=ufw state=present" -b
   ansible vault -m ufw -a "rule=allow port=8200 from_ip=203.0.113.0/24" -b
   ```

3. **Enable Audit Logging**:

   ```bash
   # After Vault is running
   vault audit enable file file_path=/var/log/vault/audit.log
   ```

## 📚 Additional Resources

### Official Documentation

- [Ansible Documentation](https://docs.ansible.com/)
- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault Installation Guide](https://developer.hashicorp.com/vault/docs/install)
- [Vault Configuration](https://developer.hashicorp.com/vault/docs/configuration)

### Role Documentation

- [Vault Role README](roles/vault/README.md)
- [Systemd Role README](roles/systemd/README.md)

### Community Resources

- [Ansible Galaxy](https://galaxy.ansible.com/)
- [HashiCorp Learn](https://learn.hashicorp.com/vault)
- [Vault Community Forum](https://discuss.hashicorp.com/c/vault/)

---

**Last Updated**: January 2026
