# Ansible Role: Superuser

Creates Django superuser account for NetBox administrative access on Debian/Ubuntu systems.

## Description

This role creates an administrative superuser account for NetBox using Django's management command. It handles:

- Superuser account creation with credentials from Vault
- Idempotent operation (won't fail if user exists)
- Secure credential handling
- Email configuration for admin account

## Requirements

- **OS**: Debian 12+, Ubuntu 22.04+
- **Privileges**: Root or sudo access required
- **Dependencies**:
  - NetBox installed and configured
  - PostgreSQL database with migrations complete
  - Python virtual environment with Django

## Role Variables

### Default Variables

Variables used by this role (defined in parent playbook):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `netbox_superuser_name` | `admin` | Django superuser username |
| `netbox_superuser_email` | `admin@localhost` | Superuser email address |
| `netbox_superuser_password` | From Vault | Superuser password |
| `netbox_install_dir` | `/opt/netbox` | NetBox installation directory |
| `netbox_user` | `netbox` | System user to run commands as |

### Variable Customization

You can override these variables in your playbook:

```yaml
- hosts: netbox
  roles:
    - role: superuser
      vars:
        netbox_superuser_name: root
        netbox_superuser_email: admin@example.com
        netbox_superuser_password: "{{ vault_netbox_admin_password }}"
```

## Dependencies

This role depends on:

- **netbox** role (must be installed and configured)
- **postgresql** role (database must be running)
- **systemd** role (optional, services should be running)

## Tasks Overview

### 1. Check if Superuser Exists

Checks if the superuser account already exists:

```bash
python3 manage.py shell -c "from django.contrib.auth import get_user_model; \
User = get_user_model(); \
exit(0 if User.objects.filter(username='admin').exists() else 1)"
```

### 2. Create Superuser

Creates superuser only if it doesn't exist:

```bash
python3 manage.py shell -c "from django.contrib.auth import get_user_model; \
User = get_user_model(); \
User.objects.create_superuser('admin', 'admin@localhost', 'password')"
```

**Note**: This is idempotent - it won't fail if the user already exists.

## Handlers

This role typically doesn't need handlers as it's a one-time setup.

## Example Playbook

### Basic Usage

```yaml
---
- name: Create NetBox superuser
  hosts: netbox
  become: true

  vars:
    netbox_superuser_name: admin
    netbox_superuser_email: admin@localhost
    netbox_superuser_password: "{{ vault_netbox_admin_password }}"

  roles:
    - postgresql
    - redis
    - netbox
    - systemd
    - superuser
```

### Custom Admin Account

```yaml
---
- name: Create custom NetBox admin
  hosts: netbox
  become: true

  vars:
    netbox_superuser_name: root
    netbox_superuser_email: netbox-admin@company.com
    netbox_superuser_password: "{{ vault_netbox_root_password }}"

  roles:
    - postgresql
    - redis
    - netbox
    - systemd
    - superuser
```

### Multiple Admins

```yaml
---
- name: Create multiple NetBox admins
  hosts: netbox
  become: true

  tasks:
    - name: Create first admin
      include_role:
        name: superuser
      vars:
        netbox_superuser_name: admin1
        netbox_superuser_email: admin1@company.com
        netbox_superuser_password: "{{ vault_admin1_password }}"
    
    - name: Create second admin
      include_role:
        name: superuser
      vars:
        netbox_superuser_name: admin2
        netbox_superuser_email: admin2@company.com
        netbox_superuser_password: "{{ vault_admin2_password }}"
```

## Post-Installation Verification

After role execution, verify superuser:

```bash
# Check if user exists
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
user = User.objects.get(username='admin')
print(f'Username: {user.username}')
print(f'Email: {user.email}')
print(f'Is superuser: {user.is_superuser}')
print(f'Is staff: {user.is_staff}')
print(f'Is active: {user.is_active}')
"

# Or query directly
python3 manage.py shell
>>> from django.contrib.auth import get_user_model
>>> User = get_user_model()
>>> User.objects.filter(is_superuser=True)
>>> exit()
```

## Login to NetBox

Access NetBox web interface:

1. **Open browser**: `http://<container-ip>`
2. **Click "Log In"** in top right
3. **Enter credentials**:
   - Username: `admin`
   - Password: (from Vault)
4. **Access admin interface**: Navigate to Admin → Administration

## Managing Superusers

### Create Additional Superuser Manually

```bash
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py createsuperuser
# Follow prompts
```

### Change Superuser Password

```bash
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py changepassword admin
# Enter new password twice
```

### List All Superusers

```bash
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
for user in User.objects.filter(is_superuser=True):
    print(f'{user.username} - {user.email}')
"
```

### Delete Superuser

```bash
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
User.objects.get(username='admin').delete()
"
```

## Troubleshooting

### Superuser Creation Fails

**Error**: `UNIQUE constraint failed: users_user.username`

**Cause**: User already exists

**Solution**:

```bash
# Check if user exists
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
print(User.objects.filter(username='admin').exists())
"

# Delete and recreate if needed
python3 manage.py shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
User.objects.filter(username='admin').delete()
"

# Re-run role
ansible-playbook site.yml --tags superuser
```

### Can't Login with Credentials

**Error**: "Please enter a correct username and password"

**Possible Causes**:

1. Wrong password
2. User not created
3. User not active
4. User not marked as staff/superuser

**Solution**:

```bash
# Verify user exists and is active
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
try:
    user = User.objects.get(username='admin')
    print(f'User found: {user.username}')
    print(f'Is active: {user.is_active}')
    print(f'Is staff: {user.is_staff}')
    print(f'Is superuser: {user.is_superuser}')
except User.DoesNotExist:
    print('User does not exist!')
"

# Reset password
python3 manage.py changepassword admin

# Or activate user
python3 manage.py shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
user = User.objects.get(username='admin')
user.is_active = True
user.is_staff = True
user.is_superuser = True
user.save()
"
```

### Database Connection Error

**Error**: `django.db.utils.OperationalError: could not connect to server`

**Solution**:

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test database connection
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python3 manage.py dbshell
# Should connect to PostgreSQL
\q

# Check NetBox configuration
python3 manage.py check --database default
```

## Security Considerations

### Password Security

- Store superuser password in Vault or Ansible Vault
- Never commit passwords to git
- Use strong passwords (minimum 12 characters)
- Consider password rotation policy

### Example Vault Storage

```bash
# Store in HashiCorp Vault
vault kv put secrets/netbox/config \
  superuser_name="admin" \
  superuser_email="admin@localhost" \
  superuser_password="$(openssl rand -base64 32)"

# Retrieve in playbook
netbox_superuser_password: "{{ lookup('community.general.hashi_vault', 'secret=secrets/data/netbox/config:superuser_password') }}"
```

### Access Control

After initial setup:

1. **Create individual user accounts** for each admin
2. **Assign appropriate permissions** (don't give everyone superuser)
3. **Use groups** for role-based access control
4. **Enable audit logging** to track admin actions
5. **Consider 2FA** for admin accounts (NetBox Enterprise)

## User Permissions

Superuser has full access to:

- All NetBox models and objects
- Django admin interface
- API with full read/write permissions
- Background tasks and reports
- User and permission management
- System configuration

For regular users, create accounts via:

- Django admin interface: `/admin/`
- NetBox admin page: `/admin/users/user/`
- API: `/api/users/users/`

## Files and Directories

| Path | Owner | Permissions | Description |
| ---- | ----- | ----------- | ----------- |
| `/opt/netbox/netbox/manage.py` | netbox:netbox | 755 | Django management command |

## Integration with Authentication Systems

### LDAP Authentication

NetBox supports LDAP for user authentication:

```python
# In configuration.py
REMOTE_AUTH_BACKEND = 'netbox.authentication.LDAPBackend'
```

### SSO Authentication

For SAML/OAuth2 authentication:

```python
# In configuration.py
REMOTE_AUTH_BACKEND = 'netbox.authentication.RemoteUserBackend'
REMOTE_AUTH_HEADER = 'HTTP_X_REMOTE_USER'
```

**Note**: Superuser is still needed for initial setup and emergency access.

## References

- [Django createsu peruser](https://docs.djangoproject.com/en/stable/ref/django-admin/#createsuperuser)
- [NetBox User Management](https://docs.netbox.dev/en/stable/administration/permissions/)
- [NetBox Authentication](https://docs.netbox.dev/en/stable/configuration/authentication/)
- [Django Admin Documentation](https://docs.djangoproject.com/en/stable/ref/contrib/admin/)

## Tags

This role supports Ansible tags:

- `superuser` - Run all superuser tasks
- `users` - User management tasks

Usage:

```bash
ansible-playbook site.yml --tags superuser
```

## License

MIT

## Author

HomeLab Infrastructure Team
