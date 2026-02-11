# Grafana LXC Container Deployment

Grafana observability and visualization platform deployed in Proxmox LXC container with Vault integration and data persistence.

## Features

- **Grafana OSS** – Open-source observability platform from official APT repository
- **Data Persistence** – Bind mount for `/var/lib/grafana` (SQLite DB, plugins, sessions)
- **InfluxDB Integration** – Pre-configured for time-series data visualization
- **Vault Integration** – Secrets management via HashiCorp Vault
- **NetBox Registration** – Automatic IPAM and inventory tracking
- **Unprivileged Container** – Enhanced security with UID 900 → 100900 mapping
- **Security Hardened** – SSH keys, UFW firewall, environment variable password

## Quick Start

1. **Set admin password**:

   ```bash
   export GRAFANA_ADMIN_PASSWORD="your-secure-password"
   ```

2. **Deploy**:

   ```bash
   ./deploy.sh deploy
   ```

3. **Access Grafana**:
   - Web UI: `http://<container-ip>:3000`
   - Default user: `admin`
   - Password: (what you set above)

## Configuration

### Terraform Variables (`terraform.tfvars`)

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `lxc_id` | `106` | Container VMID |
| `lxc_hostname` | `grafana` | Container hostname |
| `lxc_ip_address` | `192.0.2.106/24` | Static IP with CIDR |
| `lxc_memory` | `1024` | RAM in MB (1GB recommended) |
| `lxc_cpu_cores` | `2` | CPU cores |
| `lxc_disk_size` | `10` | Root disk size in GB |
| `lxc_grafana_data_mount_volume` | `/rpool/data/grafana` | Host path for data |

### Providing Admin Password

Three methods (in order of precedence):

1. **Environment Variable** (Recommended for automation):

   ```bash
   export GRAFANA_ADMIN_PASSWORD="secure-password"
   ./deploy.sh deploy
   ```

2. **Interactive Prompt** (Recommended for manual deployment):

   ```bash
   ./deploy.sh deploy
   # Script will prompt securely (input hidden)
   ```

3. **Ansible Extra Vars** (Alternative method):

   ```bash
   cd ansible
   ansible-playbook -i inventory.yml site.yml -e "grafana_admin_password=xxx"
   ```

> [!WARNING]
> Never hardcode the password in files or commit it to version control!

### UID Mapping (Unprivileged Container)

| Inside Container | On Proxmox Host |
| ---------------- | --------------- |
| grafana (UID 900) | 100900 |
| root (UID 0) | 100000 |

**Host bind mount permissions** are automatically set by the deployment script:

```bash
# Automatically configured during deployment
chown -R 100900:100900 /rpool/data/grafana
```

> [!NOTE]
> See the main [README.md](../README.md#unprivileged-containers--uid-mapping) for more details on UID mapping.

## Ports

| Port | Protocol | Description |
| ---- | -------- | ----------- |
| 22 | TCP | SSH |
| 3000 | TCP | Grafana Web UI |

## Data Persistence

Grafana data is stored in a bind mount:

| Data | Host Path | Container Path |
| ---- | --------- | -------------- |
| Grafana data | `/rpool/data/grafana` | `/var/lib/grafana` |

This includes:

- SQLite database (`grafana.db`)
- Plugins
- Sessions
- Dashboards
- Data source configurations

Data persists across container recreation.

## Post-Deployment

### Add InfluxDB Data Source

1. Navigate to **Configuration → Data Sources**
2. Click **Add data source**
3. Select **InfluxDB**
4. Configure:
   - **Query Language**: Flux
   - **URL**: `http://<influxdb-ip>:8086`
   - **Organization**: `homelab` (or your org)
   - **Token**: (generate from InfluxDB)
5. Click **Save & Test**

### Install Plugins

Via Grafana UI:

- Navigate to **Configuration → Plugins**
- Browse and install plugins

Via CLI (SSH into container):

```bash
grafana-cli plugins install <plugin-id>
sudo systemctl restart grafana-server
```

### Change Admin Password

```bash
ssh ansible@<container-ip>
grafana-cli admin reset-admin-password <new-password>
```

## Troubleshooting

### Container Won't Start

**Cause**: Bind mount path doesn't exist on host.

**Solution**:

```bash
ssh root@<proxmox-host>
mkdir -p /rpool/data/grafana
chown -R 100900:100900 /rpool/data/grafana
```

### Grafana Service Fails

**Cause**: Permission issues with bind mounts.

**Solution**: Verify host directory permissions:

```bash
# On Proxmox host
ls -la /rpool/data/grafana
# Should be owned by 100900:100900
```

### Connection Refused on Port 3000

**Cause**: Grafana not running or firewall blocking.

**Solution**:

```bash
ssh ansible@<container-ip>
sudo systemctl status grafana-server
sudo ufw status
```

## Backup Recommendations

1. **Proxmox Snapshots**: Use Proxmox backup for container-level backups
2. **Data Directory Backup**: Backup `/rpool/data/grafana` on host
3. **Dashboard Export**: Export dashboards via Grafana UI as JSON

## Maintenance

### Upgrade Grafana

```bash
ssh ansible@<container-ip>
sudo apt update
sudo apt upgrade grafana
sudo systemctl restart grafana-server
```

### Check Logs

```bash
sudo journalctl -u grafana-server -f
```

## Security Considerations

- ✅ Unprivileged container (UID mapping)
- ✅ Password via environment variable (not hardcoded)
- ✅ SSH key-only authentication
- ✅ UFW firewall enabled
- ⚠️ Consider HTTPS/TLS for production (use reverse proxy via lxc_npm)
- ⚠️ Consider authentication integration (LDAP/OAuth) for production

## Related Projects

- **lxc_influxdb** – Time-series database for Grafana data source
- **lxc_npm** – Nginx Proxy Manager for HTTPS/TLS termination
- **lxc_vault** – HashiCorp Vault for secrets management

## License

MIT
