#!/usr/bin/env bash
# =============================================================================
# InfluxDB LXC - Quick Reference Commands
# =============================================================================
# Usage: source QUICKREF.sh  (or just read for reference)
# =============================================================================

# -----------------------------------------------------------------------------
# Deployment Commands
# -----------------------------------------------------------------------------

# Interactive menu
# ./deploy.sh

# Full deployment (Vault → Terraform → Ansible)
# ./deploy.sh deploy

# Dry-run / plan only
# ./deploy.sh plan

# Check status
# ./deploy.sh status

# Destroy infrastructure
# ./deploy.sh destroy

# Ansible only (requires VAULT_TOKEN)
# export VAULT_TOKEN=$(vault print token)
# ./deploy.sh ansible

# Terraform only (no Ansible)
# ./deploy.sh terraform

# -----------------------------------------------------------------------------
# InfluxDB CLI Commands (run on container)
# -----------------------------------------------------------------------------

# Login to InfluxDB CLI
# influx auth login --host http://localhost:8086

# List buckets
# influx bucket list

# Create a new bucket (30 day retention)
# influx bucket create -n metrics -r 30d -o homelab

# Delete a bucket
# influx bucket delete -n <bucket_name>

# List users
# influx user list

# Create user
# influx user create -n <username> -o homelab

# Change password
# influx user password -n <username>

# Write data
# influx write -b <bucket> -o homelab 'cpu,host=server01 value=0.64'

# Query data (Flux)
# influx query 'from(bucket:"default") |> range(start:-1h)'

# -----------------------------------------------------------------------------
# Service Management (run on container)
# -----------------------------------------------------------------------------

# Check service status
# sudo systemctl status influxdb

# Restart InfluxDB
# sudo systemctl restart influxdb

# View logs
# sudo journalctl -u influxdb -f

# Check port
# ss -tlnp | grep 8086

# -----------------------------------------------------------------------------
# Backup & Restore
# -----------------------------------------------------------------------------

# Backup all data
# influx backup /backup/influxdb-$(date +%Y%m%d)

# Restore from backup
# influx restore /backup/influxdb-20260123

# -----------------------------------------------------------------------------
# Useful URLs
# -----------------------------------------------------------------------------

# InfluxDB UI: http://<container-ip>:8086
# Health check: http://<container-ip>:8086/health
# API v2 docs: http://<container-ip>:8086/docs

echo "InfluxDB Quick Reference loaded. See QUICKREF.sh for commands."
