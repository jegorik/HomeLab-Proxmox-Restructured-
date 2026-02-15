# Remote Promtail Installation

Automated Ansible playbook for installing Promtail on remote LXC containers and VMs, configured to push logs to a secured Grafana Loki instance via HTTPS with Basic Authentication.

## Features

- **Automated Installation** – Installs Promtail from official Grafana APT repository
- **Secure Configuration** – HTTPS + Basic Auth for Loki push endpoint
- **Flexible Inventory** – Support for multiple hosts with per-host job names
- **Idempotent** – Safe to run multiple times

## Prerequisites

- Ansible 2.15+ installed on control machine
- SSH access to target hosts
- Target hosts running Debian/Ubuntu
- Loki instance secured with NPM + Basic Auth (see [lxc_grafana_loki](../../lxc_grafana_loki/README.md))

## Quick Start

1. **Copy inventory template**:

   ```bash
   cp inventory.yml.example inventory.yml
   ```

2. **Edit inventory** with your target hosts:

   ```yaml
   all:
     hosts:
       my-lxc:
         ansible_host: 192.0.2.100
         ansible_user: ansible
         promtail_job_name: my_lxc_logs
   ```

3. **Run playbook**:

   ```bash
   ansible-playbook -i inventory.yml playbook.yml \
     -e promtail_loki_url=https://loki.example.com \
     -e promtail_basic_auth_password=<password-from-htpasswd>
   ```

## Configuration

### Required Variables

| Variable | Description | Example |
| ---------- | ------------- | --------- |
| `promtail_loki_url` | Loki endpoint URL | `https://loki.example.com` |
| `promtail_basic_auth_password` | Password from NPM htpasswd | (from `htpasswd` command) |

### Optional Variables (per-host in inventory)

| Variable | Default | Description |
| ---------- | ------------- | --------- |
| `promtail_job_name` | `{{ ansible_hostname }}` | Job label for logs |
| `promtail_log_paths` | `/var/log/*.log` | Log files to collect |
| `promtail_basic_auth_user` | `promtail` | Basic Auth username |

### Example: Custom Log Paths

```yaml
all:
  hosts:
    nginx-server:
      ansible_host: 192.0.2.100
      promtail_job_name: nginx_logs
      promtail_log_paths:
        - /var/log/nginx/*.log
        - /var/log/nginx/access.log
```

## Verification

After running the playbook:

```bash
# SSH to target host
ssh ansible@<target-host>

# Check Promtail status
sudo systemctl status promtail

# Check Promtail logs
sudo journalctl -u promtail -f

# Verify logs are being pushed to Loki
# (check Grafana Explore with query: {job="<your-job-name>"})
```

## Troubleshooting

### Promtail Can't Push Logs (401 Unauthorized)

**Cause**: Wrong Basic Auth password

**Solution**:

1. Verify password matches NPM htpasswd file
2. Re-run playbook with correct password:

   ```bash
   ansible-playbook -i inventory.yml playbook.yml \
     -e promtail_basic_auth_password=<correct-password>
   ```

### No Logs Appearing in Grafana

**Cause**: Log paths don't exist or Promtail can't read them

**Solution**:

```bash
# SSH to target host
ssh ansible@<target-host>

# Check Promtail positions file
cat /tmp/positions.yaml

# Check Promtail logs for errors
sudo journalctl -u promtail -n 50
```

### Connection Refused to Loki

**Cause**: Network issue or wrong Loki URL

**Solution**:

```bash
# Test connectivity from target host
curl -I https://loki.example.com/ready

# Should return: 200 OK
```

## Uninstall

To remove Promtail from a host:

```bash
ansible -i inventory.yml <hostname> -m apt -a "name=promtail state=absent" -b
ansible -i inventory.yml <hostname> -m file -a "path=/etc/promtail state=absent" -b
```

## Related Documentation

- [lxc_grafana_loki](../../lxc_grafana_loki/README.md) – Loki deployment and security setup
- [Main README](../../README.md) – HomeLab infrastructure overview
