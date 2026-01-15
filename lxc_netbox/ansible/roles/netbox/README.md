# Ansible Role: NetBox

Installs and configures NetBox DCIM/IPAM platform with Vault integration on Debian/Ubuntu systems.

## Description

This role automates the installation of NetBox from the official GitHub repository. It handles:

- System dependency installation (Python, build tools, libraries)
- NetBox source download from GitHub
- Python virtual environment creation
- Python package installation
- NetBox configuration with Vault secrets integration
- Django SECRET_KEY management
- Database migrations
- Static files collection
- Gunicorn WSGI server configuration

## Requirements

- **OS**: Debian 12+, Ubuntu 22.04+
- **Privileges**: Root or sudo access required
- **Network**: Internet connectivity for downloads
- **Dependencies**:
  - PostgreSQL 17+ (installed by `postgresql` role)
  - Redis 7+ (installed by `redis` role)
  - Python 3.11+
  - Git
- **Vault**: HashiCorp Vault with SECRET_KEY stored

## Role Variables

### Default Variables

Variables used by this role (defined in parent playbook):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `netbox_version` | `v4.4.9` | NetBox version (GitHub tag) |
| `netbox_install_dir` | `/opt/netbox` | NetBox installation directory |
| `netbox_user` | `netbox` | System user for NetBox process |
| `netbox_group` | `netbox` | System group for NetBox process |
| `netbox_secret_key` | From Vault | Django SECRET_KEY (must be 50+ chars) |
| `netbox_database_name` | `netbox` | PostgreSQL database name |
| `netbox_database_user` | `netbox` | PostgreSQL database user |
| `netbox_database_password` | From Vault | Database password |
| `netbox_superuser_name` | `admin` | Django admin username |
| `netbox_superuser_email` | `admin@localhost` | Django admin email |
| `netbox_superuser_password` | From Vault | Django admin password |
| `netbox_allowed_hosts` | `['*']` | Django ALLOWED_HOSTS |

### Variable Customization

You can override these variables in your playbook:

```yaml
- hosts: netbox
  roles:
    - role: netbox
      vars:
        netbox_version: v4.5.0
        netbox_allowed_hosts: ['netbox.example.com', '192.168.1.100']
```

## Dependencies

This role depends on:

- **postgresql** role (must run first)
- **redis** role (must run first)
- System packages: `python3`, `python3-pip`, `python3-venv`, `git`

## Templates

### configuration.py.j2

NetBox configuration template. Generates `/opt/netbox/netbox/netbox/configuration.py`:

```python
ALLOWED_HOSTS = ['*']

DATABASE = {
    'NAME': 'netbox',
    'USER': 'netbox',
    'PASSWORD': '{{ netbox_database_password }}',
    'HOST': 'localhost',
    'PORT': '',
}

REDIS = {
    'tasks': {
        'HOST': 'localhost',
        'PORT': 6379,
        'DATABASE': 0,
    },
    'caching': {
        'HOST': 'localhost',
        'PORT': 6379,
        'DATABASE': 1,
    },
}

SECRET_KEY = '{{ netbox_secret_key }}'
```

### gunicorn.py.j2

Gunicorn WSGI configuration. Generates `/opt/netbox/gunicorn.py`:

```python
bind = '127.0.0.1:8001'
workers = 4
threads = 2
timeout = 120
max_requests = 5000
max_requests_jitter = 500
```

## Tasks Overview

### 1. Install Dependencies

Installs required system packages:

- `python3`, `python3-pip`, `python3-venv`, `python3-dev`
- `gcc`, `g++`, `make`, `libxml2-dev`, `libxslt1-dev`
- `libffi-dev`, `libpq-dev`, `libssl-dev`, `zlib1g-dev`
- `git`, `wget`, `curl`

### 2. Create System User

Creates `netbox` system user with:

- Home directory: `/opt/netbox`
- Shell: `/bin/bash` (needed for Python venv)
- System account

### 3. Download NetBox

Clones NetBox from GitHub:

```bash
git clone --depth 1 --branch v4.4.9 \
  https://github.com/netbox-community/netbox.git \
  /opt/netbox
```

### 4. Create Python Virtual Environment

- Creates Python venv in `/opt/netbox/venv`
- Upgrades pip, setuptools, wheel
- Installs NetBox Python dependencies

### 5. Deploy Configuration

- Generates `configuration.py` from template
- Sets SECRET_KEY from Vault
- Configures database and Redis connections

### 6. Run Migrations

Runs Django database migrations:

```bash
python3 manage.py migrate
```

### 7. Collect Static Files

Collects static files for web serving:

```bash
python3 manage.py collectstatic --no-input
```

### 8. Configure Gunicorn

Deploys Gunicorn configuration for WSGI serving.

## Handlers

### restart netbox service

Restarts the NetBox systemd service when configuration changes.

**Trigger**: When `configuration.py` or `gunicorn.py` is modified

**Note**: Requires systemd role to manage the service.

## Example Playbook

### Basic Usage

```yaml
---
- name: Install NetBox
  hosts: netbox
  become: true

  vars:
    netbox_version: v4.4.9
    netbox_secret_key: "{{ vault_netbox_secret_key }}"
    netbox_database_password: "{{ vault_netbox_db_password }}"

  roles:
    - postgresql
    - redis
    - netbox
```

### Custom Configuration

```yaml
---
- name: Install NetBox with custom settings
  hosts: netbox
  become: true

  vars:
    netbox_version: v4.5.0
    netbox_allowed_hosts:
      - 'netbox.internal'
      - '192.168.1.100'
    netbox_superuser_name: root
    netbox_superuser_email: root@example.com

  roles:
    - postgresql
    - redis
    - netbox
```

## Post-Installation Verification

After role execution, verify NetBox:

```bash
# Check NetBox installation
ls -la /opt/netbox

# Verify Python environment
/opt/netbox/venv/bin/python --version

# Check installed packages
/opt/netbox/venv/bin/pip list | grep -i netbox

# Test NetBox management command
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py showmigrations

# Test Gunicorn
/opt/netbox/venv/bin/gunicorn --version

# Check configuration
python3 manage.py check
```

## NetBox Configuration

### SECRET_KEY Generation

NetBox requires a SECRET_KEY for Django. Generate with:

```bash
openssl rand -base64 64 | tr -d '\n'
```

Store in Vault:

```bash
vault kv put secrets/netbox/config \
  secret_key="$(openssl rand -base64 64 | tr -d '\n')"
```

### Database Configuration

PostgreSQL must be running with:

- Database: `netbox`
- User: `netbox`
- Password: Stored in Vault

### Redis Configuration

NetBox uses two Redis databases:

- Database 0: Task queue (background jobs)
- Database 1: Caching (query and page cache)

## Troubleshooting

### Installation Fails

```bash
# Check Python version
python3 --version  # Must be 3.11+

# Check dependencies
dpkg -l | grep -E 'python3|libpq|redis|postgresql'

# Manually install dependencies
cd /opt/netbox
source venv/bin/activate
pip install -r requirements.txt
```

### Migration Errors

```bash
# Check database connection
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py dbshell  # Should connect to PostgreSQL

# Run migrations manually
python3 manage.py migrate --plan
python3 manage.py migrate

# Check migration status
python3 manage.py showmigrations
```

### SECRET_KEY Issues

```bash
# Verify SECRET_KEY length
cd /opt/netbox/netbox
python3 -c "from netbox import configuration; print(len(configuration.SECRET_KEY))"
# Should be 50+ characters

# Generate new key if needed
openssl rand -base64 64 | tr -d '\n'
```

### Static Files Not Found

```bash
# Collect static files manually
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py collectstatic --no-input

# Check static files directory
ls -la /opt/netbox/netbox/static/
```

### Gunicorn Won't Start

```bash
# Test Gunicorn manually
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
gunicorn -c /opt/netbox/gunicorn.py netbox.wsgi

# Check Gunicorn configuration
python3 -c "import sys; sys.path.append('/opt/netbox'); import gunicorn; print(gunicorn)"

# Verify WSGI application
python3 manage.py check --deploy
```

## Files and Directories

| Path | Owner | Permissions | Description |
| ---- | ----- | ----------- | ----------- |
| `/opt/netbox/` | netbox:netbox | 755 | NetBox installation root |
| `/opt/netbox/venv/` | netbox:netbox | 755 | Python virtual environment |
| `/opt/netbox/netbox/` | netbox:netbox | 755 | NetBox application code |
| `/opt/netbox/netbox/netbox/configuration.py` | netbox:netbox | 640 | NetBox configuration (sensitive!) |
| `/opt/netbox/gunicorn.py` | netbox:netbox | 644 | Gunicorn WSGI configuration |
| `/opt/netbox/netbox/static/` | netbox:netbox | 755 | Static files (CSS, JS, images) |
| `/opt/netbox/netbox/media/` | netbox:netbox | 755 | User uploads |

## Security Considerations

- **SECRET_KEY** must be kept secret and stored in Vault
- **Database password** must be stored in Vault
- `configuration.py` has restricted permissions (640)
- NetBox runs as non-privileged user `netbox`
- Gunicorn listens on localhost only (127.0.0.1:8001)
- Use Nginx reverse proxy for external access

## Integration with Other Roles

### Execution Order

1. **postgresql** - Create database
2. **redis** - Start cache server
3. **netbox** - Install application (this role)
4. **systemd** - Create systemd services
5. **nginx** - Configure reverse proxy
6. **superuser** - Create admin user

### Service Dependencies

NetBox requires:

- PostgreSQL running on port 5432
- Redis running on port 6379
- Gunicorn running on port 8001 (managed by systemd)

## NetBox Management

### Common Management Commands

```bash
# Activate virtual environment
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate

# Create superuser
python3 manage.py createsuperuser

# Check for pending migrations
python3 manage.py showmigrations

# Clear cache
python3 manage.py invalidate all

# Shell access
python3 manage.py shell

# Database shell
python3 manage.py dbshell
```

## Upgrading NetBox

To upgrade to a new version:

```bash
# Update role variable
vars:
  netbox_version: v4.5.0

# Re-run playbook
ansible-playbook site.yml --tags netbox

# Or manually
cd /opt/netbox
git fetch --all --tags
git checkout v4.5.0
source venv/bin/activate
pip install --upgrade -r requirements.txt
python3 netbox/manage.py migrate
python3 netbox/manage.py collectstatic --no-input
sudo systemctl restart netbox netbox-rq
```

## References

- [NetBox Official Documentation](https://docs.netbox.dev/)
- [NetBox Installation Guide](https://docs.netbox.dev/en/stable/installation/)
- [NetBox GitHub Repository](https://github.com/netbox-community/netbox)
- [Django Documentation](https://docs.djangoproject.com/)
- [Gunicorn Documentation](https://docs.gunicorn.org/)

## Tags

This role supports Ansible tags:

- `netbox` - Run all NetBox tasks
- `config` - Configuration tasks only
- `migrate` - Database migration only

Usage:

```bash
ansible-playbook site.yml --tags netbox
ansible-playbook site.yml --tags config
```

## License

MIT

## Author

HomeLab Infrastructure Team
