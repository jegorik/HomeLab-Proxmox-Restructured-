# Remote Promtail Installation

Automated Ansible playbook for installing Promtail on remote hosts and pushing logs to a secured Grafana Loki instance via HTTPS with Basic Authentication.

## Features

- **Universal** – Works on any Linux distribution (Debian, Ubuntu, RHEL, Rocky, Alma, OpenSUSE, Alpine, etc.)
- **Binary Installation** – Downloads pre-compiled binary from GitHub Releases (no package manager dependency)
- **Multi-Architecture** – Auto-detects `amd64`, `arm64`, `armv7`
- **Secure** – HTTPS + Basic Auth for Loki push endpoint; dedicated `promtail` system user; password retrieved from HashiCorp Vault (never passed on CLI)
- **Hardened Systemd Unit** – `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem`, `CAP_DAC_READ_SEARCH`
- **Idempotent** – Safe to run multiple times

## Prerequisites

- Ansible 2.15+ on control machine
- SSH access to target hosts (any Linux with systemd)
- Internet access on target hosts (to download binary from GitHub)
- HashiCorp Vault deployed in your infrastructure (see [lxc_vault](../../lxc_vault/README.md)) — required for secure password retrieval
- Loki instance secured with NPM + Basic Auth (see [lxc_grafana_loki](../../lxc_grafana_loki/README.md))

## Secure Quick Start (via Vault — recommended)

### 1. Store Loki credentials in Vault

```bash
vault kv put secret/promtail/loki \
  url="https://loki.example.com" \
  username="promtail" \
  password="<your-loki-basic-auth-password>"
```

### 2. Copy and edit inventory

```bash
cp inventory.yml.example inventory.yml
# Edit inventory.yml with your target hosts
```

### 3. (Optional) Create deploy.conf to skip prompts

```bash
cp deploy.conf.example deploy.conf
# Edit deploy.conf:
#   vault_addr=https://vault.example.com:8200
#   vault_username=operator
#   vault_secret_path=secret/promtail/loki
```

### 4. Run the deployment script

```bash
chmod +x deploy.sh
./deploy.sh run
```

The script will:
1. Authenticate to Vault (reuse existing token or prompt for password)
2. Retrieve the Loki URL and password from Vault KV — **never passing them on the command line**
3. Write credentials to a temporary file and pass it to `ansible-playbook -e @file`
4. Delete the temporary file immediately after the run

### deploy.sh commands

```
./deploy.sh          # Interactive menu
./deploy.sh run      # Vault auth + ansible-playbook
./deploy.sh check    # Dry-run (--check, no changes)
./deploy.sh status   # Ping all hosts
./deploy.sh help     # Show help
```

#### Environment shortcuts (avoid interactive prompts in CI/CD):

```bash
export VAULT_ADDR=https://vault.example.com:8200
export VAULT_USERNAME=operator
export VAULT_TOKEN=$(vault print token)   # if already authenticated
./deploy.sh run
```

---

## Manual Quick Start (without Vault)

> **Security warning**: This method passes the password on the command line.
> It is visible in shell history and `ps` output. Use the Vault method above in production.



## Configuration

### Required Variables

| Variable | Description | Example |
| --- | --- | --- |
| `promtail_loki_url` | Loki endpoint URL | `https://loki.example.com` |
| `promtail_basic_auth_password` | Password from NPM htpasswd | (from `htpasswd` command) |

### Optional Variables

| Variable | Default | Description |
| --- | --- | --- |
| `promtail_version` | `3.3.2` | Promtail version to install |
| `promtail_job_name` | `{{ ansible_hostname }}` | Job label for logs in Grafana |
| `promtail_log_paths` | `/var/log/*.log` | Log files to collect |
| `promtail_basic_auth_user` | `promtail` | Basic Auth username |
| `promtail_http_port` | `9080` | Promtail HTTP port |

### Pinning a Specific Version

```bash
ansible-playbook -i inventory.yml playbook.yml \
  -e promtail_version=3.4.0 \
  -e promtail_loki_url=https://loki.example.com \
  -e promtail_basic_auth_password=<password>
```

### Example: Custom Log Paths per Host

```yaml
all:
  hosts:
    nginx-server:
      ansible_host: 192.0.2.100
      promtail_job_name: nginx_logs
      promtail_log_paths:
        - /var/log/nginx/access.log
        - /var/log/nginx/error.log
    opensuse-vm:
      ansible_host: 192.0.2.101
      promtail_job_name: opensuse_logs
      promtail_log_paths:
        - /var/log/messages
        - /var/log/warn
```

## Installation Details

The playbook installs Promtail by:

1. Downloading the pre-compiled binary from [GitHub Releases](https://github.com/grafana/loki/releases)
2. Creating a dedicated `promtail` system user and group
3. Installing a hardened systemd service unit
4. Deploying configuration with Basic Auth credentials

**Installed paths:**

| Path | Description |
| --- | --- |
| `/usr/local/bin/promtail` | Binary |
| `/etc/promtail/config.yml` | Configuration |
| `/etc/promtail/.loki-password` | Password file (mode 0600) |
| `/var/lib/promtail/positions.yaml` | Positions file |
| `/etc/systemd/system/promtail.service` | Systemd unit |

## Verification

After running the playbook:

```bash
# Check Promtail status
sudo systemctl status promtail

# Follow Promtail logs
sudo journalctl -u promtail -f

# Verify binary version
/usr/local/bin/promtail --version

# Check Grafana Explore with query:
# {job="<your-job-name>"}
```

## Troubleshooting

### 401 Unauthorized

**Cause**: Wrong Basic Auth password.

```bash
# Re-run with correct password
ansible-playbook -i inventory.yml playbook.yml \
  -e promtail_basic_auth_password=<correct-password>
```

### No Logs in Grafana

**Cause**: Log paths don't exist or Promtail can't read them.

```bash
# Check positions file
sudo cat /var/lib/promtail/positions.yaml

# Check Promtail logs for errors
sudo journalctl -u promtail -n 50
```

### Binary Download Fails

**Cause**: No internet access on target host, or wrong version.

```bash
# Test connectivity from target host
curl -I https://github.com/grafana/loki/releases

# Or pre-download and place binary manually at:
# /usr/local/bin/promtail
```

### Connection Refused to Loki

```bash
# Test connectivity from target host
curl -I https://loki.example.com/ready
# Should return: 200 OK
```

## Uninstall

```bash
# Stop and disable service
ansible -i inventory.yml all -m systemd -a "name=promtail state=stopped enabled=false" -b

# Remove files
ansible -i inventory.yml all -m file -a "path={{ item }} state=absent" -b \
  -e '{"item": "/usr/local/bin/promtail"}'
ansible -i inventory.yml all -m file -a "path=/etc/promtail state=absent" -b
ansible -i inventory.yml all -m file -a "path=/etc/systemd/system/promtail.service state=absent" -b
ansible -i inventory.yml all -m user -a "name=promtail state=absent remove=true" -b
```

## Related Documentation

- [lxc_vault](../../lxc_vault/README.md) – Vault deployment (required for secure password retrieval)
- [Promtail GitHub Releases](https://github.com/grafana/loki/releases) – Available versions
