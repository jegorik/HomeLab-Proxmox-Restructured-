# Grafana Loki LXC Container Deployment

Grafana Loki log aggregation system deployed in Proxmox LXC container with Vault integration and data persistence.

## Features

- **Grafana Loki** – Horizontally scalable log aggregation from official APT repository
- **Promtail** – Log shipping agent for collecting and forwarding local logs
- **Data Persistence** – Bind mounts for `/var/lib/loki/chunks` and `/var/lib/loki/rules`
- **Vault Integration** – Secrets management via HashiCorp Vault
- **NetBox Registration** – Automatic IPAM and inventory tracking
- **Unprivileged Container** – Enhanced security with UID 900 → 100900 mapping
- **Security Hardened** – SSH keys, UFW firewall, minimal attack surface

## Quick Start

1. **Deploy**:

   ```bash
   ./deploy.sh deploy
   ```

2. **Verify Loki is running**:
   - HTTP API: `http://<container-ip>:3100/ready`
   - Metrics: `http://<container-ip>:3100/metrics`

## Configuration

### Terraform Variables (`terraform.tfvars`)

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `lxc_id` | `108` | Container VMID |
| `lxc_hostname` | `grafana-loki` | Container hostname |
| `lxc_ip_address` | `dhcp` | Static IP with CIDR |
| `lxc_memory` | `2048` | RAM in MB |
| `lxc_cpu_cores` | `2` | CPU cores |
| `lxc_disk_size` | `20` | Root disk size in GB |
| `lxc_grafana_loki_chunks_mount_volume` | `/rpool/data/grafana_loki/chunks` | Host path for chunks data |
| `lxc_grafana_loki_rules_mount_volume` | `/rpool/data/grafana_loki/rules` | Host path for rules data |

### UID Mapping (Unprivileged Container)

| Inside Container | On Proxmox Host |
| ---------------- | --------------- |
| loki (UID 900) | 100900 |
| root (UID 0) | 100000 |

**Host bind mount permissions** are automatically set by the deployment script:

```bash
# Automatically configured during deployment
chown -R 100900:100900 /rpool/datastore/grafana_loki/chunks
chown -R 100900:100900 /rpool/datastore/grafana_loki/rules
```

> [!NOTE]
> See the main [README.md](../README.md#unprivileged-containers--uid-mapping) for more details on UID mapping.

## Ports

| Port | Protocol | Description |
| ---- | -------- | ----------- |
| 22 | TCP | SSH |
| 3100 | TCP | Loki HTTP API |
| 9096 | TCP | Loki gRPC (internal) |
| 9080 | TCP | Promtail HTTP (internal) |

## Data Persistence

Loki data is stored in bind mounts:

| Data | Host Path | Container Path |
| ---- | --------- | -------------- |
| Chunks | `/rpool/datastore/grafana_loki/chunks` | `/var/lib/loki/chunks` |
| Rules | `/rpool/datastore/grafana_loki/rules` | `/var/lib/loki/rules` |

Data persists across container recreation.

## Post-Deployment

### Add Loki as Data Source in Grafana

1. Navigate to Grafana → **Connections → Data Sources**
2. Click **Add data source**
3. Select **Loki**
4. Configure:
   - **URL**: `http://<loki-container-ip>:3100`
5. Click **Save & Test**

### Test Log Ingestion

Push a test log entry:

```bash
curl -X POST http://<container-ip>:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)000000000'","hello loki"]]}]}'
```

Query logs:

```bash
curl -G http://<container-ip>:3100/loki/api/v1/query \
  --data-urlencode 'query={job="test"}'
```

### Loki Configuration

The Loki config file is deployed via Ansible template to `/etc/loki/config.yml`. Key settings:

- **Retention**: 31 days (`744h`) by default
- **Storage**: Filesystem backend using bind-mounted directories
- **Schema**: TSDB with v13 schema
- **Auth**: Disabled (single-tenant mode)

To customize, edit `ansible/roles/grafana_loki/defaults/main.yml` and redeploy:

```bash
./deploy.sh ansible
```

## Troubleshooting

### Container Won't Start

**Cause**: Bind mount paths don't exist on host.

**Solution**:

```bash
ssh root@<proxmox-host>
mkdir -p /rpool/datastore/grafana_loki/{chunks,rules}
chown -R 100900:100900 /rpool/datastore/grafana_loki
```

### Loki Service Fails

**Cause**: Permission issues with bind mounts.

**Solution**: Verify host directory permissions:

```bash
# On Proxmox host
ls -la /rpool/datastore/grafana_loki/
# Should be owned by 100900:100900
```

### Connection Refused on Port 3100

**Cause**: Loki not running or firewall blocking.

**Solution**:

```bash
ssh ansible@<container-ip>
sudo systemctl status loki
sudo ufw status
```

### Loki Reports "WAL replay" on Startup

This is normal after restart. Loki replays the Write-Ahead Log to recover in-flight data. Wait for the `/ready` endpoint to return `200`.

## Backup Recommendations

1. **Proxmox Snapshots**: Use Proxmox backup for container-level backups
2. **Data Directory Backup**: Backup chunks and rules directories on host
3. **Config Backup**: Loki config is managed by Ansible (stored in git)

## Maintenance

### Upgrade Loki

```bash
ssh ansible@<container-ip>
sudo apt update
sudo apt upgrade loki promtail
sudo systemctl restart loki promtail
```

### Check Logs

```bash
# Loki logs
sudo journalctl -u loki -f

# Promtail logs
sudo journalctl -u promtail -f
```

### Check Loki Readiness

```bash
curl -s http://localhost:3100/ready
# Should return "ready"
```

## Security Considerations

- ✅ Unprivileged container (UID mapping)
- ✅ SSH key-only authentication
- ✅ UFW firewall enabled
- ✅ No authentication secrets required (unlike Grafana)
- ⚠️ Auth disabled by default — restrict network access or enable auth for production
- ⚠️ Consider HTTPS/TLS for production (use reverse proxy via lxc_npm)

## Related Projects

- **lxc_grafana** – Visualization platform (add Loki as data source)
- **lxc_npm** – Nginx Proxy Manager for HTTPS/TLS termination
- **lxc_vault** – HashiCorp Vault for secrets management
- **lxc_influxdb** – Time-series database for metrics

## License

MIT
