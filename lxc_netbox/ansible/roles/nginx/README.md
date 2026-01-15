# Ansible Role: Nginx

Configures Nginx reverse proxy for NetBox on Debian/Ubuntu systems.

## Description

This role installs and configures Nginx as a reverse proxy for NetBox. It handles:

- Nginx installation from official repositories
- NetBox site configuration with automatic port detection
- Proxy settings optimized for NetBox
- Static file serving configuration
- WebSocket support for NetBox real-time features

## Requirements

- **OS**: Debian 12+, Ubuntu 22.04+
- **Privileges**: Root or sudo access required
- **Network**: Internet connectivity for package downloads
- **Dependencies**:
  - NetBox installed and running on port 8001
  - Systemd services (netbox.service, netbox-rq.service)

## Role Variables

### Default Variables

Variables used by this role (defined in parent playbook):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `nginx_listen_port` | Auto-detect (80 or 8300) | HTTP listening port |
| `netbox_server_name` | `_` (catch-all) | Server hostname |
| `netbox_gunicorn_bind` | `127.0.0.1:8001` | Upstream Gunicorn address |
| `netbox_install_dir` | `/opt/netbox` | NetBox installation directory |
| `netbox_max_body_size` | `25M` | Maximum upload file size |

### Variable Customization

You can override these variables in your playbook:

```yaml
- hosts: netbox
  roles:
    - role: nginx
      vars:
        netbox_server_name: netbox.example.com
        netbox_max_body_size: 50M
```

## Dependencies

This role depends on:

- **netbox** role (must be installed first)
- **systemd** role (services must be running)

## Templates

### netbox.nginx.conf.j2

Nginx site configuration for NetBox reverse proxy:

```nginx
upstream netbox {
    server 127.0.0.1:8001;
}

server {
    listen 80;  # Or 8300 if port 80 is in use
    server_name _;
    
    client_max_body_size 25M;
    
    location / {
        proxy_pass http://netbox;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /static/ {
        alias /opt/netbox/netbox/static/;
    }
    
    location /media/ {
        alias /opt/netbox/netbox/media/;
    }
}
```

## Port Auto-Detection

The role automatically detects available ports:

1. **Checks port 80** - Default HTTP port
2. **Falls back to 8300** - Alternative port if 80 is in use
3. **Uses Ansible facts** - Checks existing listeners

## Tasks Overview

### 1. Install Nginx

Installs Nginx web server from official repositories:

- `nginx` - Main package
- `nginx-common` - Common files

### 2. Detect Available Port

Checks which port is available:

- Prefers port 80 (standard HTTP)
- Falls back to 8300 if 80 is occupied

### 3. Deploy Configuration

Creates Nginx site configuration:

- `/etc/nginx/sites-available/netbox`
- Symbolic link: `/etc/nginx/sites-enabled/netbox`

### 4. Remove Default Site

Disables default Nginx site to avoid conflicts:

```bash
rm /etc/nginx/sites-enabled/default
```

### 5. Test Configuration

Validates Nginx configuration before restarting:

```bash
nginx -t
```

### 6. Enable and Start Service

- Enables Nginx to start on boot
- Starts or restarts Nginx service

## Handlers

### reload nginx

Reloads Nginx configuration without dropping connections.

**Trigger**: When site configuration is modified

### restart nginx

Restarts Nginx service completely.

**Trigger**: When Nginx package is updated

## Example Playbook

### Basic Usage

```yaml
---
- name: Configure Nginx for NetBox
  hosts: netbox
  become: true

  roles:
    - postgresql
    - redis
    - netbox
    - systemd
    - nginx
```

### Custom Domain

```yaml
---
- name: Configure Nginx with custom domain
  hosts: netbox
  become: true

  vars:
    netbox_server_name: netbox.internal.lan
    netbox_max_body_size: 50M

  roles:
    - postgresql
    - redis
    - netbox
    - systemd
    - nginx
```

### Specific Port

```yaml
---
- name: Force Nginx to use port 8300
  hosts: netbox
  become: true

  vars:
    nginx_listen_port: 8300

  roles:
    - postgresql
    - redis
    - netbox
    - systemd
    - nginx
```

## Post-Installation Verification

After role execution, verify Nginx:

```bash
# Check Nginx status
sudo systemctl status nginx

# Test configuration
sudo nginx -t

# Check listening ports
sudo netstat -tlnp | grep nginx
# Or
sudo ss -tlnp | grep nginx

# View access logs
sudo tail -f /var/log/nginx/access.log

# View error logs
sudo tail -f /var/log/nginx/error.log

# Check NetBox site configuration
sudo cat /etc/nginx/sites-available/netbox

# Test HTTP response
curl -I http://localhost
curl http://localhost
```

## Nginx Configuration Details

### Proxy Headers

Essential headers for NetBox:

```nginx
proxy_set_header Host $http_host;                    # Original host
proxy_set_header X-Real-IP $remote_addr;             # Client IP
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  # Proxy chain
proxy_set_header X-Forwarded-Proto $scheme;          # HTTP/HTTPS
```

### Static Files

Direct serving bypasses Gunicorn:

```nginx
location /static/ {
    alias /opt/netbox/netbox/static/;
    expires 30d;
    add_header Cache-Control "public, immutable";
}
```

### Upload Size

Controls maximum file upload size:

```nginx
client_max_body_size 25M;  # Adjust for your needs
```

## Troubleshooting

### Nginx Won't Start

```bash
# Check service status
sudo systemctl status nginx

# View error logs
sudo journalctl -u nginx -n 50

# Test configuration
sudo nginx -t

# Check for syntax errors
sudo nginx -T
```

### Port Already in Use

```bash
# Check what's using port 80
sudo netstat -tlnp | grep :80
sudo lsof -i :80

# Kill conflicting process
sudo systemctl stop apache2  # If Apache is running

# Or use alternative port
# Set nginx_listen_port: 8300 in playbook
```

### 502 Bad Gateway

**Error**: Nginx returns 502 when accessing NetBox

**Causes**:

- Gunicorn not running
- Wrong upstream address
- Firewall blocking connection

**Solution**:

```bash
# Check Gunicorn is running
sudo systemctl status netbox.service

# Test Gunicorn directly
curl http://127.0.0.1:8001

# Check Nginx error log
sudo tail -f /var/log/nginx/error.log

# Verify upstream configuration
grep upstream /etc/nginx/sites-available/netbox

# Restart services
sudo systemctl restart netbox.service nginx.service
```

### 403 Forbidden on Static Files

```bash
# Check file permissions
ls -la /opt/netbox/netbox/static/

# Fix ownership
sudo chown -R netbox:www-data /opt/netbox/netbox/static/

# Fix permissions
sudo chmod -R 755 /opt/netbox/netbox/static/

# Check Nginx user
ps aux | grep nginx | head -1

# Verify Nginx can read files
sudo -u www-data cat /opt/netbox/netbox/static/netbox.css
```

### 413 Request Entity Too Large

**Error**: File upload fails with 413 error

**Solution**:

```bash
# Increase upload size in Nginx
sudo vim /etc/nginx/sites-available/netbox
# Change: client_max_body_size 50M;

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

### SSL/TLS Configuration

To add HTTPS support:

```nginx
server {
    listen 443 ssl http2;
    server_name netbox.example.com;
    
    ssl_certificate /etc/ssl/certs/netbox.crt;
    ssl_certificate_key /etc/ssl/private/netbox.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # ... rest of configuration
}

server {
    listen 80;
    server_name netbox.example.com;
    return 301 https://$server_name$request_uri;
}
```

## Files and Directories

| Path | Owner | Permissions | Description |
| ---- | ----- | ----------- | ----------- |
| `/etc/nginx/nginx.conf` | root:root | 644 | Main Nginx configuration |
| `/etc/nginx/sites-available/netbox` | root:root | 644 | NetBox site configuration |
| `/etc/nginx/sites-enabled/netbox` | root:root | 777 (symlink) | Enabled site link |
| `/var/log/nginx/access.log` | www-data:adm | 640 | HTTP access log |
| `/var/log/nginx/error.log` | www-data:adm | 640 | Error log |
| `/var/log/nginx/netbox.access.log` | www-data:adm | 640 | NetBox access log |

## Performance Tuning

### For High Traffic Sites

```nginx
upstream netbox {
    server 127.0.0.1:8001;
    keepalive 32;
}

server {
    # ... existing config
    
    # Proxy performance
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
    proxy_busy_buffers_size 8k;
    
    # Connection settings
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    
    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    gzip_min_length 1000;
}
```

### Static File Caching

```nginx
location /static/ {
    alias /opt/netbox/netbox/static/;
    expires 30d;
    add_header Cache-Control "public, immutable";
    access_log off;
}
```

## Load Balancing

For multiple NetBox instances:

```nginx
upstream netbox {
    least_conn;
    server 127.0.0.1:8001;
    server 127.0.0.1:8002;
    server 127.0.0.1:8003;
}
```

## Monitoring

### Access Logs

```bash
# View access logs
sudo tail -f /var/log/nginx/access.log

# Count requests
sudo grep -c "GET" /var/log/nginx/access.log

# Top IPs
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head

# Response codes
sudo awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c
```

### Error Logs

```bash
# View error logs
sudo tail -f /var/log/nginx/error.log

# Count errors by type
sudo grep -E "error|warn" /var/log/nginx/error.log | cut -d' ' -f4- | sort | uniq -c

# Recent errors
sudo grep error /var/log/nginx/error.log | tail -20
```

## Security Headers

For production deployments:

```nginx
server {
    # ... existing config
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Hide Nginx version
    server_tokens off;
}
```

## References

- [Nginx Official Documentation](https://nginx.org/en/docs/)
- [NetBox Nginx Configuration](https://docs.netbox.dev/en/stable/installation/5-http-server/)
- [Nginx Reverse Proxy Guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
- [Nginx Performance Tuning](https://www.nginx.com/blog/tuning-nginx/)

## Tags

This role supports Ansible tags:

- `nginx` - Run all Nginx tasks
- `webserver` - Configuration tasks only

Usage:

```bash
ansible-playbook site.yml --tags nginx
```

## License

MIT

## Author

HomeLab Infrastructure Team
