# Grafana Ansible Role

Ansible role for installing and configuring Grafana OSS on Debian/Ubuntu systems.

## Requirements

- Debian 12 (Bookworm) or Ubuntu 22.04+
- Ansible 2.15+
- Internet access for APT repository

## Role Variables

### Required Variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `grafana_admin_password` | **REQUIRED** | Initial admin password (provide via `GRAFANA_ADMIN_PASSWORD` env var, inventory, or extra vars) |

### Optional Variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `grafana_admin_user` | `admin` | Admin username |
| `grafana_http_port` | `3000` | HTTP port for Grafana web UI |
| `grafana_domain` | `localhost` | Domain name |
| `grafana_protocol` | `http` | Protocol (http or https) |

## Dependencies

- `community.general` collection (for UFW module)

## Example Playbook

```yaml
---
- hosts: grafana_servers
  become: true
  
  roles:
    - role: grafana
      grafana_admin_password: "{{ lookup('env', 'GRAFANA_ADMIN_PASSWORD') }}"
```

## Service User

This role creates a `grafana` user with fixed UID/GID 900 for unprivileged container compatibility:

- Container UID 900 → Host UID 100900
- Ensures consistent permissions for bind-mounted data directories

## Tags

- `grafana` - All Grafana tasks
- `grafana:install` - Installation tasks only
- `grafana:config` - Configuration tasks only
- `grafana:service` - Service management tasks
- `grafana:firewall` - Firewall configuration

## License

MIT
