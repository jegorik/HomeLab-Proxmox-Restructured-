# Ansible Role: Redis

Installs and configures Redis 7 cache server for NetBox on Debian/Ubuntu systems.

## Description

This role automates the installation of Redis from the official Debian/Ubuntu repositories. It handles:

- Redis server installation
- Redis configuration for NetBox caching and task queue
- Service management and startup configuration
- Basic security hardening

## Requirements

- **OS**: Debian 12+, Ubuntu 22.04+
- **Privileges**: Root or sudo access required
- **Network**: Internet connectivity for package downloads
- **Dependencies**:
  - `python3`

## Role Variables

### Default Variables

Variables used by this role (defined in parent playbook):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `redis_bind_address` | `127.0.0.1` | IP address Redis listens on |
| `redis_port` | `6379` | Redis port |
| `redis_maxmemory` | `256mb` | Maximum memory for Redis |
| `redis_maxmemory_policy` | `allkeys-lru` | Eviction policy when maxmemory reached |
| `redis_password` | (none) | Optional Redis authentication password |

### Variable Customization

You can override these variables in your playbook:

```yaml
- hosts: netbox
  roles:
    - role: redis
      vars:
        redis_maxmemory: 512mb
        redis_password: "{{ vault_redis_password }}"
```

## Dependencies

None. This is a standalone role, but must run before the NetBox role.

## Tasks Overview

### 1. Install Redis

Installs Redis server package from official repositories:

- `redis-server` - Redis server daemon
- `redis-tools` - Redis CLI tools

### 2. Configure Redis

Configures Redis for NetBox usage:

- Binds to localhost (default)
- Sets memory limit for caching
- Configures LRU eviction policy
- Disables persistence (optional, for pure cache usage)

### 3. Enable Service

- Starts Redis service
- Enables Redis to start on boot
- Verifies service is running

## Handlers

### restart redis

Restarts the Redis systemd service when configuration changes.

**Trigger**: When `/etc/redis/redis.conf` is modified

## Example Playbook

### Basic Usage

```yaml
---
- name: Install Redis for NetBox
  hosts: netbox
  become: true

  roles:
    - redis
```

### With Authentication

```yaml
---
- name: Install Redis with password
  hosts: netbox
  become: true

  vars:
    redis_password: "{{ vault_redis_password }}"
    redis_maxmemory: 512mb

  roles:
    - redis
```

### High Memory Configuration

```yaml
---
- name: Install Redis with more memory
  hosts: netbox
  become: true

  vars:
    redis_maxmemory: 1gb
    redis_maxmemory_policy: allkeys-lru

  roles:
    - redis
```

## Post-Installation Verification

After role execution, verify Redis:

```bash
# Check service status
sudo systemctl status redis-server

# Test Redis connection
redis-cli ping
# Expected: PONG

# Check Redis info
redis-cli info server

# Monitor Redis in real-time
redis-cli monitor

# Check memory usage
redis-cli info memory
```

## Redis Configuration

Default configuration in `/etc/redis/redis.conf`:

```conf
bind 127.0.0.1 ::1           # Listen on localhost only
port 6379                     # Default Redis port
maxmemory 256mb               # Maximum memory limit
maxmemory-policy allkeys-lru  # LRU eviction when full

# Optional for pure cache (no persistence)
save ""                       # Disable RDB snapshots
appendonly no                 # Disable AOF
```

## Security Considerations

- Redis listens on localhost only by default (safe for single-host deployment)
- No authentication required for localhost connections (optional)
- Memory limit prevents Redis from consuming all system RAM
- Firewall blocks external access to port 6379

### Optional: Enable Authentication

If you want to add authentication:

```yaml
vars:
  redis_password: "your-secure-password"
```

Then NetBox configuration needs:

```python
REDIS = {
    'tasks': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': 'your-secure-password',
        'DATABASE': 0,
    },
    'caching': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': 'your-secure-password',
        'DATABASE': 1,
    },
}
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u redis-server -n 50

# Check Redis logs
sudo tail -f /var/log/redis/redis-server.log

# Verify configuration syntax
redis-server /etc/redis/redis.conf --test-memory 1
```

### Connection Refused

```bash
# Check if Redis is running
sudo systemctl status redis-server

# Check if Redis is listening
sudo netstat -tlnp | grep 6379

# Test connection
redis-cli ping

# Check bind address
grep bind /etc/redis/redis.conf
```

### Memory Issues

```bash
# Check current memory usage
redis-cli info memory | grep used_memory_human

# Check maxmemory setting
redis-cli config get maxmemory

# Monitor memory in real-time
watch -n 1 'redis-cli info memory | grep used_memory_human'
```

### High CPU Usage

```bash
# Check slow queries
redis-cli slowlog get 10

# Monitor commands
redis-cli monitor

# Check connected clients
redis-cli client list
```

## Files and Directories

| Path | Owner | Permissions | Description |
| ---- | ----- | ----------- | ----------- |
| `/etc/redis/redis.conf` | root:root | 644 | Main configuration file |
| `/var/lib/redis/` | redis:redis | 755 | Data directory (if persistence enabled) |
| `/var/log/redis/` | redis:redis | 755 | Log directory |
| `/var/run/redis/` | redis:redis | 755 | Runtime files (PID, socket) |

## Integration with NetBox

NetBox uses Redis for two purposes:

1. **Caching** (database 1) - Cache database queries and rendered pages
2. **Task Queue** (database 0) - Background job processing with RQ (Redis Queue)

NetBox configuration in `configuration.py`:

```python
REDIS = {
    'tasks': {
        'HOST': 'localhost',
        'PORT': 6379,
        'DATABASE': 0,
        'SSL': False,
    },
    'caching': {
        'HOST': 'localhost',
        'PORT': 6379,
        'DATABASE': 1,
        'SSL': False,
    },
}
```

## Performance Tuning

### For Large NetBox Deployments

```yaml
vars:
  redis_maxmemory: 2gb                    # More cache memory
  redis_maxmemory_policy: allkeys-lru     # Keep frequently accessed data
  redis_tcp_backlog: 511                  # Connection queue size
  redis_timeout: 300                      # Client timeout (seconds)
```

### For Development/Testing

```yaml
vars:
  redis_maxmemory: 128mb                  # Minimal memory
  redis_save_enabled: false               # No persistence needed
```

## Redis Maintenance

### Clear All Data

```bash
# Clear all databases
redis-cli FLUSHALL

# Clear specific database (e.g., cache)
redis-cli -n 1 FLUSHDB
```

### Monitor Performance

```bash
# Real-time stats
redis-cli --stat

# Monitor all commands
redis-cli monitor

# Get info about specific section
redis-cli info replication
redis-cli info clients
```

## References

- [Redis Official Documentation](https://redis.io/documentation)
- [NetBox Redis Requirements](https://docs.netbox.dev/en/stable/installation/2-redis/)
- [Redis Security](https://redis.io/topics/security)
- [Redis Memory Optimization](https://redis.io/topics/memory-optimization)

## Tags

This role supports Ansible tags:

- `redis` - Run all Redis tasks
- `cache` - Configuration tasks only

Usage:

```bash
ansible-playbook site.yml --tags redis
```

## License

MIT

## Author

HomeLab Infrastructure Team
