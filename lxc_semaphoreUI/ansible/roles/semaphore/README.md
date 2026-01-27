# Ansible Role: Semaphore

Installs and configures Semaphore UI on Debian-based systems.

## Requirements

- Ansible 2.9+
- Target config: Debian 12+

## Role Variables

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `semaphore_version` | `latest` | Version to install (or 'latest') |
| `semaphore_port` | `3000` | HTTP listening port |
| `semaphore_db_dialect` | `bolt` | Database backend (bolt, mysql, postgres) |
| `semaphore_admin_enable` | `true` | Enable admin user creation |
| `semaphore_admin_username` | `admin` | Admin username |

## Dependencies

None.

## Example Playbook

```yaml
- hosts: servers
  roles:
    - role: semaphore
      vars:
        semaphore_version: "2.10.11"
```
