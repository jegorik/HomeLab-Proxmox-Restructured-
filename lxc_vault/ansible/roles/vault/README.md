# Ansible Role: Vault

Installs and configures HashiCorp Vault secrets management server on Debian/Ubuntu systems.

## Description

This role automates the installation of HashiCorp Vault from the official HashiCorp APT repository. It handles:

- System dependency installation
- HashiCorp GPG key and repository setup
- Vault package installation
- System user and group creation
- Directory structure creation with proper permissions
- Vault configuration file deployment

## Requirements

- **OS**: Debian 12+, Ubuntu 22.04+
- **Privileges**: Root or sudo access required
- **Network**: Internet connectivity for package downloads
- **Dependencies**:
  - `python3`
  - `gpg`
  - `wget`
  - `curl`

## Role Variables

### Default Variables

Variables used by this role (defined in parent playbook):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `vault_keyring_dir` | `/usr/share/keyrings` | Directory for GPG keyrings |
| `vault_data_dir` | `/var/lib/vault/data` | Vault data storage directory |
| `vault_config_dir` | `/etc/vault.d` | Vault configuration directory |
| `vault_config_file` | `vault.hcl.j2` | Template filename for Vault config |
| `vault_config_path` | `/etc/vault.d/vault.hcl` | Full path to Vault config file |
| `vault_user` | `vault` | System user for Vault process |
| `vault_group` | `vault` | System group for Vault process |

### Variable Customization

You can override these variables in your playbook:

```yaml
- hosts: vault
  roles:
    - role: vault
      vars:
        vault_data_dir: /mnt/vault-data
        vault_user: vaultservice
```

## Dependencies

None. This is a standalone role.

## Templates

### vault.hcl.j2

Vault server configuration template. Generates `/etc/vault.d/vault.hcl` with:

```hcl
ui = true                    # Enable Web UI
disable_mlock = true         # Required for LXC containers

storage "file" {             # File-based storage backend
  path = "/var/lib/vault/data"
}

listener "tcp" {             # HTTP listener (TLS disabled)
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr = "http://0.0.0.0:8200"
```

**Note**: TLS is disabled by default. For production, configure TLS or use a reverse proxy.

## Tasks Overview

### 1. Install Dependencies

Installs required system packages:

- `python3`, `python3-pip`, `python3-venv`, `python3-dev`
- `wget`, `gpg`, `curl`, `unzip`
- `lsb-release`, `ca-certificates`, `sudo`

### 2. Setup HashiCorp Repository

- Creates keyring directory
- Downloads and installs HashiCorp GPG key
- Adds HashiCorp APT repository

### 3. Install Vault

Installs Vault package from HashiCorp repository.

### 4. Create System User

Creates `vault` system user with:

- Home directory: `/etc/vault.d`
- Shell: `/bin/false` (no login)
- System account (no UID in user range)

### 5. Create Directories

Creates required directories with proper ownership:

- `/var/lib/vault/data` (755, vault:vault)
- `/etc/vault.d` (750, vault:vault)

### 6. Deploy Configuration

Deploys Vault configuration from template with:

- Owner: vault:vault
- Permissions: 0640

## Handlers

### restart vault service

Restarts the Vault systemd service when configuration changes.

**Trigger**: When `vault.hcl` is modified

**Note**: This handler is defined but requires the systemd role to actually manage the service.

## Example Playbook

### Basic Usage

```yaml
---
- name: Install HashiCorp Vault
  hosts: vault
  become: true

  vars:
    vault_data_dir: /var/lib/vault/data
    vault_config_dir: /etc/vault.d
    vault_user: vault
    vault_group: vault

  roles:
    - role: vault
```

### With Custom Variables

```yaml
---
- name: Install Vault on Custom Path
  hosts: vault
  become: true

  vars:
    vault_data_dir: /mnt/secure-storage/vault
    vault_config_dir: /opt/vault/config
    vault_user: vaultsvc
    vault_group: vaultsvc

  roles:
    - role: vault
```

### With Tags

```yaml
---
- name: Install Vault Components
  hosts: vault
  become: true

  roles:
    - role: vault
      tags:
        - vault
        - install
        - security
```

Execute specific parts:

```bash
# Install only dependencies
ansible-playbook site.yml --tags dependencies

# Install only Vault package
ansible-playbook site.yml --tags vault

# Configure only (skip installation)
ansible-playbook site.yml --tags configuration
```

## Directory Structure

```text
roles/vault/
├── README.md             # This file
├── meta/
│   └── main.yml          # Role metadata
├── tasks/
│   └── main.yml          # Installation tasks
├── templates/
│   └── vault.hcl.j2      # Vault configuration template
└── handlers/
    └── main.yml          # Service restart handler
```

## File Permissions

After role execution:

```text
/etc/vault.d/              # 750 vault:vault
└── vault.hcl              # 640 vault:vault

/var/lib/vault/            # 755 vault:vault
└── data/                  # 755 vault:vault
```

## Idempotency

This role is idempotent. Running it multiple times produces the same result:

- ✅ Packages already installed → No change
- ✅ User already exists → No change
- ✅ Directories exist → No change
- ✅ Configuration unchanged → No change
- ✅ Safe to re-run after updates

## Post-Installation

After this role completes:

1. **Vault is installed** but not running yet
2. **Configuration is in place**: `/etc/vault.d/vault.hcl`
3. **User created**: `vault` system user
4. **Directories created**: Storage and config directories
5. **Next step**: Run `systemd` role to start and initialize Vault

## Security Considerations

### File System Security

- Configuration directory (`/etc/vault.d`) has restricted permissions (750)
- Configuration file is not world-readable (640)
- Data directory owned by `vault` user
- Vault runs as non-privileged user

### Network Security

- Default configuration listens on all interfaces (0.0.0.0)
- No TLS configured (HTTP only)
- **Production**: Use reverse proxy with TLS or configure Vault TLS

### Memory Protection

- `disable_mlock = true` for LXC compatibility
- In VMs, set to `false` and add `IPC_LOCK` capability

## Troubleshooting

### Repository Issues

**Problem**: HashiCorp repository not accessible

```bash
# Test connectivity
curl -I https://apt.releases.hashicorp.com/

# Manually add repository
wget -qO- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  tee /etc/apt/sources.list.d/hashicorp.list
```

### Permission Issues

**Problem**: Vault can't write to data directory

```bash
# Check ownership
ls -la /var/lib/vault/

# Fix if needed
chown -R vault:vault /var/lib/vault/
chmod 755 /var/lib/vault/data
```

### GPG Key Issues

**Problem**: GPG key verification fails

```bash
# Remove old key
rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Remove repository config
rm -f /etc/apt/sources.list.d/hashicorp.list

# Re-run playbook
ansible-playbook site.yml --tags vault
```

## Version Information

- **Vault Version**: Installed from official repository (latest stable)
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

- **systemd**: Manages Vault service and initialization (required after this role)

## Additional Resources

- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault Installation Guide](https://developer.hashicorp.com/vault/docs/install)
- [Vault Configuration Reference](https://developer.hashicorp.com/vault/docs/configuration)
- [Vault File Storage Backend](https://developer.hashicorp.com/vault/docs/configuration/storage/filesystem)
