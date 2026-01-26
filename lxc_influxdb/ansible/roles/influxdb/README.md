# InfluxDB Ansible Role

Installs and configures InfluxDB 2.x time-series database.

## Tasks

1. Downloads and verifies InfluxData GPG key
2. Adds InfluxData APT repository
3. Installs `influxdb2` and `influxdb2-cli` packages
4. Enables and starts `influxdb` systemd service
5. Performs initial setup (admin user, org, bucket)

## Variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `influxdb_admin_user` | `admin` | Initial admin username |
| `influxdb_admin_password` | **REQUIRED** | Initial admin password (provide via `INFLUXDB_ADMIN_PASSWORD` env var, inventory, or extra vars) |
| `influxdb_org` | `homelab` | Initial organization name |
| `influxdb_bucket` | `default` | Initial bucket name |
| `influxdb_retention` | `0` | Retention policy (0 = infinite) |

## Notes

- InfluxDB 2.x uses a single `influxdb` service (not `influxd`)
- Initial setup is idempotent - only runs if not already configured
- Data persistence requires bind mounts in Terraform configuration
- Default port: 8086 (HTTP API and UI)

## Dependencies

- Base role (for system packages)
