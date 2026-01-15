# Ansible Role: PostgreSQL

Installs and configures PostgreSQL 17 database server for NetBox on Debian/Ubuntu systems.

## Description

This role automates the installation of PostgreSQL 17 from the official PostgreSQL APT repository. It handles:

- System dependency installation
- PostgreSQL GPG key and repository setup
- PostgreSQL 17 package installation
- Database and user creation for NetBox
- PostgreSQL performance tuning for NetBox workload

## Requirements

- **OS**: Debian 12+, Ubuntu 22.04+
- **Privileges**: Root or sudo access required
- **Network**: Internet connectivity for package downloads
- **Dependencies**:
  - `python3`
  - `python3-psycopg2` (PostgreSQL Python adapter)
  - `gpg`

## Role Variables

### Default Variables

Variables used by this role (defined in parent playbook):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `netbox_database_name` | `netbox` | PostgreSQL database name |
| `netbox_database_user` | `netbox` | PostgreSQL database user |
| `netbox_database_password` | Generated or from Vault | Database user password |
| `postgresql_version` | `17` | PostgreSQL major version |
| `postgresql_keyring_dir` | `/usr/share/keyrings` | Directory for GPG keyrings |

### Variable Customization

You can override these variables in your playbook:

```yaml
- hosts: netbox
  roles:
    - role: postgresql
      vars:
        netbox_database_name: netbox_prod
        postgresql_version: 17
```

## Dependencies

None. This is a standalone role, but must run before the NetBox role.

## Tasks Overview

### 1. Install Dependencies

Installs required system packages:

- `python3`, `python3-pip`, `python3-psycopg2`
- `wget`, `gpg`, `ca-certificates`
- `lsb-release`, `gnupg`

### 2. Setup PostgreSQL Repository

- Creates keyring directory
- Downloads and installs PostgreSQL GPG key
- Adds PostgreSQL APT repository (apt.postgresql.org)

### 3. Install PostgreSQL 17

Installs PostgreSQL 17 server and client packages.

### 4. Create Database and User

- Creates `netbox` database
- Creates `netbox` user with password
- Grants all privileges on database to user
- Ensures PostgreSQL service is started and enabled

### 5. Performance Tuning (Optional)

Adjusts PostgreSQL settings for NetBox:

- `shared_buffers` - Memory for caching
- `work_mem` - Memory for query operations
- `maintenance_work_mem` - Memory for maintenance tasks

## Handlers

### restart postgresql

Restarts the PostgreSQL systemd service when configuration changes.

**Trigger**: When PostgreSQL configuration is modified

## Example Playbook

### Basic Usage

```yaml
---
- name: Install PostgreSQL for NetBox
  hosts: netbox
  become: true

  vars:
    netbox_database_name: netbox
    netbox_database_user: netbox
    netbox_database_password: "{{ vault_netbox_db_password }}"

  roles:
    - postgresql
```

### Custom Database

```yaml
---
- name: Install PostgreSQL with custom database
  hosts: netbox
  become: true

  vars:
    netbox_database_name: dcim_prod
    netbox_database_user: dcim_app
    postgresql_version: 17

  roles:
    - postgresql
```

## Post-Installation Verification

After role execution, verify PostgreSQL:

```bash
# Check service status
sudo systemctl status postgresql

# Verify PostgreSQL version
sudo -u postgres psql --version

# List databases
sudo -u postgres psql -c '\l'

# Test database connection
sudo -u postgres psql -c '\c netbox'

# Verify user
sudo -u postgres psql -c '\du'
```

## Security Considerations

- Database password should be stored in Vault or Ansible Vault
- PostgreSQL listens on localhost by default (safe for single-host deployment)
- User `netbox` has full access only to `netbox` database
- System user `postgres` is used for administrative tasks

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u postgresql -n 50

# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-17-main.log

# Verify configuration
sudo -u postgres /usr/lib/postgresql/17/bin/postgres -C config_file
```

### Connection Refused

```bash
# Check if PostgreSQL is listening
sudo netstat -tlnp | grep 5432

# Verify pg_hba.conf
sudo cat /etc/postgresql/17/main/pg_hba.conf

# Test connection
psql -h localhost -U netbox -d netbox
```

### Database Creation Fails

```bash
# Check if database exists
sudo -u postgres psql -c '\l' | grep netbox

# Manually create if needed
sudo -u postgres createdb netbox
sudo -u postgres createuser -P netbox
sudo -u postgres psql -c 'GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox;'
```

## Files and Directories

| Path | Owner | Permissions | Description |
| ---- | ----- | ----------- | ----------- |
| `/etc/postgresql/17/main/` | postgres:postgres | 755 | Configuration directory |
| `/var/lib/postgresql/17/main/` | postgres:postgres | 700 | Data directory |
| `/var/log/postgresql/` | postgres:postgres | 755 | Log directory |

## Integration with NetBox

PostgreSQL must be:

1. **Running** before NetBox installation
2. **Database created** with correct credentials
3. **Accessible** from localhost (default configuration)

The NetBox role will use these connection settings:

```python
DATABASE = {
    'NAME': 'netbox',
    'USER': 'netbox',
    'PASSWORD': '{{ netbox_database_password }}',
    'HOST': 'localhost',
    'PORT': 5432,
}
```

## References

- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/17/)
- [NetBox PostgreSQL Requirements](https://docs.netbox.dev/en/stable/installation/1-postgresql/)
- [PostgreSQL APT Repository](https://wiki.postgresql.org/wiki/Apt)

## Tags

This role supports Ansible tags:

- `postgresql` - Run all PostgreSQL tasks
- `database` - Database creation tasks only

Usage:

```bash
ansible-playbook site.yml --tags postgresql
ansible-playbook site.yml --tags database
```

## License

MIT

## Author

HomeLab Infrastructure Team
