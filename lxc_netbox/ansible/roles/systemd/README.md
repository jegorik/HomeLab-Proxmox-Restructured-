# Ansible Role: Systemd

Configures systemd service units for NetBox application services on Debian/Ubuntu systems.

## Description

This role creates and manages systemd service units for NetBox. It handles:

- NetBox web service (Gunicorn WSGI server)
- NetBox-RQ service (background task worker)
- Service dependencies and ordering
- Automatic service startup on boot
- Service restart policies

## Requirements

- **OS**: Debian 12+, Ubuntu 22.04+
- **Privileges**: Root or sudo access required
- **Dependencies**:
  - NetBox installed in `/opt/netbox`
  - Python virtual environment with dependencies
  - PostgreSQL and Redis running

## Role Variables

### Default Variables

Variables used by this role (defined in parent playbook):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `netbox_install_dir` | `/opt/netbox` | NetBox installation directory |
| `netbox_user` | `netbox` | System user for NetBox services |
| `netbox_group` | `netbox` | System group for NetBox services |
| `netbox_gunicorn_workers` | `4` | Number of Gunicorn worker processes |
| `netbox_gunicorn_bind` | `127.0.0.1:8001` | Gunicorn bind address and port |

### Variable Customization

You can override these variables in your playbook:

```yaml
- hosts: netbox
  roles:
    - role: systemd
      vars:
        netbox_gunicorn_workers: 8
        netbox_gunicorn_bind: 0.0.0.0:8001
```

## Dependencies

This role depends on:

- **netbox** role (must be installed first)
- **postgresql** role (database must be running)
- **redis** role (cache must be running)

## Templates

### netbox.service.j2

Main NetBox web service running Gunicorn WSGI server.

```ini
[Unit]
Description=NetBox WSGI Service
Documentation=https://docs.netbox.dev/
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target
Requires=postgresql.service redis-server.service

[Service]
Type=notify
User=netbox
Group=netbox
WorkingDirectory=/opt/netbox/netbox
ExecStart=/opt/netbox/venv/bin/gunicorn \
    --pid /var/tmp/netbox.pid \
    --pythonpath /opt/netbox/netbox \
    --config /opt/netbox/gunicorn.py \
    netbox.wsgi
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### netbox-rq.service.j2

NetBox background task worker using Redis Queue (RQ).

```ini
[Unit]
Description=NetBox Request Queue Worker
Documentation=https://docs.netbox.dev/
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=netbox
Group=netbox
WorkingDirectory=/opt/netbox/netbox
ExecStart=/opt/netbox/venv/bin/python3 \
    /opt/netbox/netbox/manage.py rqworker
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

## Tasks Overview

### 1. Create Service Files

Deploys systemd unit files from templates:

- `/etc/systemd/system/netbox.service` (Gunicorn web server)
- `/etc/systemd/system/netbox-rq.service` (Background worker)

### 2. Reload Systemd

Runs `systemctl daemon-reload` to register new services.

### 3. Enable Services

Enables both services to start automatically on boot:

```bash
systemctl enable netbox.service
systemctl enable netbox-rq.service
```

### 4. Start Services

Starts both services:

```bash
systemctl start netbox.service
systemctl start netbox-rq.service
```

## Handlers

### reload systemd

Reloads systemd manager configuration when service files change.

**Trigger**: When `.service` files are created or modified

### restart netbox services

Restarts both NetBox services when configuration changes.

**Trigger**: When NetBox or Gunicorn configuration changes

## Example Playbook

### Basic Usage

```yaml
---
- name: Configure NetBox systemd services
  hosts: netbox
  become: true

  roles:
    - postgresql
    - redis
    - netbox
    - systemd
```

### Custom Worker Configuration

```yaml
---
- name: Configure NetBox with more workers
  hosts: netbox
  become: true

  vars:
    netbox_gunicorn_workers: 8

  roles:
    - postgresql
    - redis
    - netbox
    - systemd
```

## Post-Installation Verification

After role execution, verify services:

```bash
# Check service status
sudo systemctl status netbox.service
sudo systemctl status netbox-rq.service

# View service logs
sudo journalctl -u netbox.service -n 50
sudo journalctl -u netbox-rq.service -n 50

# Follow logs in real-time
sudo journalctl -u netbox.service -f

# Check if services are enabled
sudo systemctl is-enabled netbox.service
sudo systemctl is-enabled netbox-rq.service

# Check if services are active
sudo systemctl is-active netbox.service
sudo systemctl is-active netbox-rq.service

# List all NetBox-related services
sudo systemctl list-units 'netbox*'
```

## Service Management

### Manual Service Control

```bash
# Start services
sudo systemctl start netbox.service
sudo systemctl start netbox-rq.service

# Stop services
sudo systemctl stop netbox.service
sudo systemctl stop netbox-rq.service

# Restart services
sudo systemctl restart netbox.service
sudo systemctl restart netbox-rq.service

# Reload NetBox configuration (graceful)
sudo systemctl reload netbox.service

# Enable on boot
sudo systemctl enable netbox.service netbox-rq.service

# Disable on boot
sudo systemctl disable netbox.service netbox-rq.service
```

### Check Service Dependencies

```bash
# View service dependencies
sudo systemctl list-dependencies netbox.service

# Check what requires this service
sudo systemctl list-dependencies --reverse netbox.service
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
sudo systemctl status netbox.service

# View detailed error logs
sudo journalctl -u netbox.service -n 100 --no-pager

# Check for configuration errors
sudo systemctl cat netbox.service

# Test Gunicorn manually
sudo -u netbox /opt/netbox/venv/bin/gunicorn \
  --config /opt/netbox/gunicorn.py \
  --pythonpath /opt/netbox/netbox \
  netbox.wsgi
```

### Service Crashes Immediately

```bash
# Check NetBox configuration
cd /opt/netbox/netbox
sudo -u netbox /opt/netbox/venv/bin/python3 manage.py check

# Verify database connectivity
sudo -u netbox /opt/netbox/venv/bin/python3 manage.py dbshell

# Check Redis connectivity
redis-cli ping

# View crash logs
sudo journalctl -u netbox.service --since "5 minutes ago"
```

### Background Worker Not Processing Jobs

```bash
# Check netbox-rq service
sudo systemctl status netbox-rq.service

# View worker logs
sudo journalctl -u netbox-rq.service -f

# Test RQ worker manually
cd /opt/netbox/netbox
sudo -u netbox /opt/netbox/venv/bin/python3 manage.py rqworker

# Check Redis queue
redis-cli -n 0 LLEN default
```

### Service Restarts Frequently

```bash
# Check for repeated crashes
sudo journalctl -u netbox.service | grep -i "restart"

# View systemd restart statistics
sudo systemctl show netbox.service | grep -i restart

# Increase restart delay
sudo systemctl edit netbox.service
# Add:
[Service]
RestartSec=30
```

### Port Already in Use

```bash
# Check what's using port 8001
sudo netstat -tlnp | grep 8001
sudo lsof -i :8001

# Kill process if needed
sudo kill -9 <PID>

# Or change Gunicorn port in gunicorn.py
vim /opt/netbox/gunicorn.py
# bind = '127.0.0.1:8002'
```

## Service Configuration

### Gunicorn Workers

Number of worker processes affects:

- **Performance**: More workers = more concurrent requests
- **Memory**: Each worker uses ~200-500MB RAM
- **CPU**: Workers should not exceed CPU cores

Recommended formula: `workers = (2 * CPU_cores) + 1`

```bash
# For 2 CPU cores: 5 workers
# For 4 CPU cores: 9 workers
# For 8 CPU cores: 17 workers
```

### Restart Policy

Services are configured with:

- `Restart=on-failure` - Restart only on crashes
- `RestartSec=10` - Wait 10 seconds before restart

For production, consider:

```ini
[Service]
Restart=always
RestartSec=30
StartLimitInterval=300
StartLimitBurst=5
```

## Files and Directories

| Path | Owner | Permissions | Description |
| ---- | ----- | ----------- | ----------- |
| `/etc/systemd/system/netbox.service` | root:root | 644 | NetBox web service unit |
| `/etc/systemd/system/netbox-rq.service` | root:root | 644 | NetBox worker service unit |
| `/var/tmp/netbox.pid` | netbox:netbox | 644 | Gunicorn PID file |

## Service Logs

### View Logs

```bash
# View all logs
sudo journalctl -u netbox.service
sudo journalctl -u netbox-rq.service

# View recent logs
sudo journalctl -u netbox.service -n 50

# Follow logs in real-time
sudo journalctl -u netbox.service -f

# View logs since specific time
sudo journalctl -u netbox.service --since "1 hour ago"
sudo journalctl -u netbox.service --since "2024-01-15 09:00:00"

# View logs with priority
sudo journalctl -u netbox.service -p err  # Only errors
sudo journalctl -u netbox.service -p warning  # Warnings and above
```

### Log Rotation

Systemd journal handles log rotation automatically. Configure in `/etc/systemd/journald.conf`:

```ini
[Journal]
SystemMaxUse=1G
SystemKeepFree=500M
MaxRetentionSec=2week
```

## Integration with Nginx

After systemd services are running, Nginx can proxy requests:

```nginx
upstream netbox {
    server 127.0.0.1:8001;
}

server {
    listen 80;
    
    location / {
        proxy_pass http://netbox;
    }
}
```

## Performance Monitoring

Monitor service performance:

```bash
# CPU and memory usage
sudo systemctl status netbox.service | grep -E "Memory|CPU"

# Detailed process info
ps aux | grep gunicorn
ps aux | grep rqworker

# Check resource limits
sudo systemctl show netbox.service | grep -i limit

# Monitor in real-time
watch -n 2 'systemctl status netbox.service netbox-rq.service'
```

## References

- [systemd Documentation](https://www.freedesktop.org/wiki/Software/systemd/)
- [NetBox Services Configuration](https://docs.netbox.dev/en/stable/installation/4-gunicorn/)
- [Gunicorn Deployment](https://docs.gunicorn.org/en/stable/deploy.html)
- [systemd.service Manual](https://www.freedesktop.org/software/systemd/man/systemd.service.html)

## Tags

This role supports Ansible tags:

- `systemd` - Run all systemd tasks
- `services` - Service management only

Usage:

```bash
ansible-playbook site.yml --tags systemd
```

## License

MIT

## Author

HomeLab Infrastructure Team
