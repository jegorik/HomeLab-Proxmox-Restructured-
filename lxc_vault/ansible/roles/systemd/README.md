# Ansible Role: Systemd

Manages HashiCorp Vault systemd service, including creation, configuration, startup, and automated initialization.

## Description

This role handles the systemd service lifecycle for HashiCorp Vault:

- Creates hardened systemd service unit file
- Enables and starts Vault service
- Waits for Vault to become ready
- Checks Vault initialization status
- Automatically initializes Vault (if not already initialized)
- Saves unseal keys and root token securely

## Requirements

- **OS**: Debian 12+, Ubuntu 22.04+ (systemd-based systems)
- **Privileges**: Root or sudo access required
- **Prerequisites**: 
  - Vault must be installed (run `vault` role first)
  - Vault configuration file at `/etc/vault.d/vault.hcl`
  - Vault user and directories must exist

## Role Variables

### Default Variables

Variables used by this role (defined in parent playbook):

| Variable | Default | Description |
|----------|---------|-------------|
| `vault_service_file` | `vault.service.j2` | Systemd unit template filename |
| `vault_service_path` | `/etc/systemd/system/vault.service` | Full path to service unit |
| `vault_config_path` | `/etc/vault.d/vault.hcl` | Vault configuration file path |

### Service Configuration

The systemd unit file includes security hardening:

```ini
[Unit]
Description=HashiCorp Vault - A tool for managing secrets
After=network-online.target
Requires=network-online.target

[Service]
Type=notify
User=vault
Group=vault
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
Restart=on-failure

# Security hardening
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
```

## Dependencies

**Required**: `vault` role must be executed before this role.

```yaml
roles:
  - vault      # Install Vault first
  - systemd    # Then configure service
```

## Templates

### vault.service.j2

Systemd unit file template with security hardening directives.

**Key Features**:
- **Type=notify**: Vault notifies systemd when ready
- **Restart=on-failure**: Auto-restart on crashes
- **Security hardening**: Multiple systemd security directives
- **Resource limits**: File descriptor and process limits

**Security Directives**:
- `ProtectSystem=full`: Read-only /usr, /boot, /efi
- `ProtectHome=read-only`: Read-only /home
- `PrivateTmp=yes`: Private /tmp namespace
- `PrivateDevices=yes`: Limited device access
- `NoNewPrivileges=yes`: Prevent privilege escalation

## Tasks Overview

### 1. Create Service Unit File

Deploys systemd unit file from template with:
- Owner: root:root
- Permissions: 0644
- Location: `/etc/systemd/system/vault.service`

### 2. Reload Systemd

Triggers daemon reload to recognize new service.

### 3. Start Vault Service

Enables and starts the Vault service:
- Enabled: Service starts on boot
- Started: Service is running now

### 4. Wait for Vault Ready

Waits for Vault to listen on port 8200:
- Host: 127.0.0.1
- Port: 8200
- Timeout: 30 seconds
- Delay: 2 seconds before checking

### 5. Check Initialization Status

Queries Vault to determine if it's already initialized using:
```bash
vault status -format=json | python3 -c "import sys, json; ..."
```

Returns: `"true"` if initialized, `"false"` if not

### 6. Initialize Vault (Conditional)

**Only runs if** Vault is not already initialized:
```bash
vault operator init > /root/vault-keys.txt
```

**Output contains**:
- 5 unseal keys (by default)
- Initial root token

### 7. Set File Permissions

Sets permissions on keys file:
- Permissions: 0600 (read/write for root only)
- Location: `/root/vault-keys.txt`

## Handlers

### reload systemd

Reloads systemd daemon configuration.

**Trigger**: When service unit file is created or modified

```yaml
- name: reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
```

## Example Playbook

### Basic Usage

```yaml
---
- name: Configure Vault Service
  hosts: vault
  become: true

  vars:
    vault_service_path: /etc/systemd/system/vault.service

  roles:
    - role: systemd
```

### Complete Deployment

```yaml
---
- name: Deploy HashiCorp Vault
  hosts: vault
  become: true

  roles:
    - role: vault      # Install Vault
    - role: systemd    # Configure and start service
```

### With Tags

```yaml
---
- name: Manage Vault Service
  hosts: vault
  become: true

  roles:
    - role: systemd
      tags:
        - systemd
        - service
        - vault
```

Execute specific parts:
```bash
# Configure service only (skip initialization)
ansible-playbook site.yml --tags service

# Initialize Vault only
ansible-playbook site.yml --tags initialize

# Start service only
ansible-playbook site.yml --tags start
```

## Vault Initialization

### Initialization Process

When Vault is initialized for the first time:

1. **Generates 5 unseal keys** (Shamir's secret sharing)
2. **Creates root token** for initial access
3. **Saves to file**: `/root/vault-keys.txt`

### Unseal Keys

- **Total keys**: 5 (default)
- **Required to unseal**: 3 (threshold)
- **Purpose**: Decrypt Vault's master key

### Root Token

- **Purpose**: Superuser access to Vault
- **Use**: Initial configuration only
- **Best practice**: Revoke after creating admin users

### Keys File Format

```
Unseal Key 1: <key1>
Unseal Key 2: <key2>
Unseal Key 3: <key3>
Unseal Key 4: <key4>
Unseal Key 5: <key5>

Initial Root Token: s.<token>

Vault initialized with 5 key shares and a key threshold of 3.
Please securely distribute the key shares printed above.
```

## Post-Role Actions

### Critical: Save Vault Keys

**Immediately after deployment**:

```bash
# Retrieve keys from container
ssh ansible@<container-ip> sudo cat /root/vault-keys.txt

# Copy output to secure password manager
# Examples: 1Password, Bitwarden, KeePass

# Delete from server
ssh ansible@<container-ip> sudo rm /root/vault-keys.txt
```

**WARNING**: If you lose the unseal keys, Vault data cannot be recovered!

### Verify Service

```bash
# Check service status
systemctl status vault

# View logs
journalctl -u vault -f

# Check Vault status
export VAULT_ADDR='http://127.0.0.1:8200'
vault status
```

### Access Vault

```bash
# Via CLI
export VAULT_ADDR='http://<container-ip>:8200'
export VAULT_TOKEN='<root-token>'
vault status

# Via Web UI
# Open: http://<container-ip>:8200
# Login with root token
```

## Directory Structure

```
roles/systemd/
├── README.md              # This file
├── meta/
│   └── main.yml          # Role metadata
├── tasks/
│   └── main.yml          # Service management tasks
├── templates/
│   └── vault.service.j2  # Systemd unit template
└── handlers/
    └── main.yml          # Daemon reload handler
```

## Idempotency

This role is idempotent with intelligent initialization:

- ✅ Service already exists → Updates if template changed
- ✅ Service already running → No restart unless needed
- ✅ **Vault already initialized → Skips initialization** ✨
- ✅ Keys file exists → No overwrite
- ✅ Safe to re-run after updates or failures

### Initialization Check

The role checks initialization status before attempting to initialize:

```yaml
- name: Check if Vault is already initialized
  shell: |
    export VAULT_ADDR='http://127.0.0.1:8200'
    vault status -format=json 2>/dev/null | \
      python3 -c "import sys, json; \
        data=json.load(sys.stdin); \
        print('true' if data.get('initialized', False) else 'false')"
  register: vault_initialized

- name: Initialize Vault
  when: vault_initialized.stdout == "false"  # Only if not initialized
  # ...
```

## Security Considerations

### Service Security

- Runs as non-root `vault` user
- Systemd security directives enabled
- Process isolation via namespaces
- Limited system access

### Keys File Security

- Located in `/root/` (root-only access)
- Permissions: 0600 (read/write root only)
- **Action required**: Move to secure location
- **Action required**: Delete from server after saving

### Best Practices

1. **Save keys immediately** after initialization
2. **Delete keys file** from server: `rm /root/vault-keys.txt`
3. **Distribute unseal keys** to multiple trusted individuals
4. **Store root token separately** from unseal keys
5. **Rotate root token** after initial configuration
6. **Create admin policies** instead of using root token
7. **Enable audit logging** for compliance

## Troubleshooting

### Service Won't Start

**Problem**: `systemctl start vault` fails

```bash
# Check service status
systemctl status vault

# View detailed logs
journalctl -u vault -n 50 --no-pager

# Test configuration
vault server -config=/etc/vault.d/vault.hcl -test

# Check file permissions
ls -la /etc/vault.d/vault.hcl
ls -la /var/lib/vault/data
```

### Port Already in Use

**Problem**: Port 8200 already bound

```bash
# Check what's using port 8200
ss -tlnp | grep 8200

# Kill conflicting process
sudo systemctl stop <service-name>

# Or change Vault port in vault.hcl
vim /etc/vault.d/vault.hcl
# listener "tcp" {
#   address = "0.0.0.0:8300"
# }
```

### Initialization Hangs

**Problem**: `vault operator init` doesn't complete

```bash
# Check Vault is actually running
systemctl status vault

# Check port is listening
ss -tlnp | grep 8200

# Try manual initialization
export VAULT_ADDR='http://127.0.0.1:8200'
vault operator init -format=json

# Check for errors in logs
journalctl -u vault -f
```

### Keys File Not Created

**Problem**: `/root/vault-keys.txt` doesn't exist

```bash
# Check if Vault is already initialized
vault status | grep Initialized

# If initialized, keys were generated earlier
# Cannot regenerate - they're unique

# If not initialized, run manually
vault operator init > /root/vault-keys.txt
chmod 600 /root/vault-keys.txt
```

### Vault Sealed After Restart

**Problem**: Vault is sealed after server reboot

This is **expected behavior**. Vault seals on restart for security.

```bash
# Unseal Vault (requires 3 of 5 keys)
export VAULT_ADDR='http://127.0.0.1:8200'
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>

# Check status
vault status
```

**Auto-unseal options**:
- AWS KMS auto-unseal
- Azure Key Vault auto-unseal
- GCP Cloud KMS auto-unseal

## Version Information

- **Systemd Version**: Any systemd-based system
- **Vault Version**: Compatible with all Vault versions
- **Tested On**:
  - Debian 12 (Bookworm)
  - Debian 13 (Trixie)
  - Ubuntu 22.04 LTS
  - Ubuntu 24.04 LTS

## License

MIT

## Author Information

Created for HomeLab infrastructure automation.

Last Updated: January 2026

## Related Roles

- **vault**: Installs Vault (must run before this role)

## Additional Resources

- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault Initialization](https://developer.hashicorp.com/vault/docs/commands/operator/init)
- [Vault Unsealing](https://developer.hashicorp.com/vault/docs/concepts/seal)
- [Systemd Service Hardening](https://www.freedesktop.org/software/systemd/man/systemd.exec.html)

