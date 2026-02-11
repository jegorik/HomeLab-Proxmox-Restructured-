# Proxmox Backup Client — Automated Backup Scripts

Automated file-level backup solution for Proxmox hosts using `proxmox-backup-client` with systemd timers and retention policies.

> **Primary Use Case:** Back up Proxmox host directories (e.g., `/rpool/datastore/*` with LXC bind mount data) to a Proxmox Backup Server on a schedule, with automatic old backup pruning.

## Overview

This project provides a lightweight, security-hardened automation layer on top of the standard `proxmox-backup-client` tool. It replaces manual backup commands with profile-based configuration, systemd timers, and automatic retention enforcement.

### Key Features

- **Profile-based** — Multiple independent backup profiles (e.g., `rpool`, `etc-config`)
- **Systemd-native scheduling** — Uses `OnCalendar` timers (no cron hacks)
- **Retention policies** — Automatic pruning: keep-last, daily, weekly, monthly
- **Security hardened** — No `eval`, no `source`, credentials separated, strict permissions
- **Lock files** — Prevents concurrent backup runs for the same profile
- **Validated configs** — Validate before first run with built-in checks
- **Structured logging** — Per-profile logs + systemd journal integration

## Directory Structure

```text
proxmox_bkup_client_script/
├── README.md                   # This documentation
├── pbs-backup.sh               # Backup runner (installed to /usr/local/bin/)
├── pbs-backup-manage.sh        # Management CLI (install/remove/status/test/run)
├── pbs-backup.conf.example     # Configuration template (copy per profile)
└── credentials.example         # Credentials template (copy per profile)
```

**Installed layout on the Proxmox host:**

```text
/usr/local/bin/pbs-backup.sh                         # Backup runner
/etc/pbs-backup/<profile>.conf                       # Config per profile
/etc/pbs-backup/<profile>.credentials                # Credentials per profile (0600)
/etc/systemd/system/pbs-backup-<profile>.service     # Systemd oneshot service
/etc/systemd/system/pbs-backup-<profile>.timer       # Systemd timer
/var/log/pbs-backup/<profile>.log                    # Backup logs
/run/lock/pbs-backup/<profile>.lock                  # Runtime lock file
```

## Quick Start

### Prerequisites

- Proxmox host with `proxmox-backup-client` installed
- A running Proxmox Backup Server with a configured datastore
- A PBS user/API token with `DatastoreBackup` + `DatastorePrune` permissions

### 1. Install a Profile

```bash
# Copy scripts to the Proxmox host (or clone repo directly)
cd /path/to/proxmox_bkup_client_script

# Install a profile named "rpool"
sudo ./pbs-backup-manage.sh install rpool
```

### 2. Configure

Edit the generated config files:

```bash
# Main configuration (server, paths, schedule, retention)
sudo nano /etc/pbs-backup/rpool.conf

# Credentials (password or API token secret)
sudo nano /etc/pbs-backup/rpool.credentials
```

**Example `/etc/pbs-backup/rpool.conf`:**

```ini
PBS_SERVER="192.0.2.181"
PBS_PORT="8007"
PBS_DATASTORE="backups"
PBS_AUTH_ID="root@pam"
PBS_FINGERPRINT=""

# Backup paths (space-separated)
# NOTE: Mount points (bind mounts) are automatically detected and traversed with --include-dev
BACKUP_PATHS="/rpool/datastore"

# Exclusion patterns (space-separated)
EXCLUDE_PATTERNS="lost+found .snapshots .cache tmp"

BACKUP_SCHEDULE="*-*-* 02:00:00"

KEEP_LAST=3
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=3
```

**Example `/etc/pbs-backup/rpool.credentials`:**

```ini
PBS_PASSWORD="your-password-here"
```

### 3. Validate & Test

```bash
# Validate config syntax and file permissions
sudo ./pbs-backup-manage.sh validate rpool

# Test connectivity to PBS server
sudo ./pbs-backup-manage.sh test rpool
```

### 4. Enable Timer

```bash
# Enable the systemd timer (starts scheduled backups)
sudo systemctl enable --now pbs-backup-rpool.timer

# Verify next run time
systemctl list-timers pbs-backup-rpool.timer
```

### 5. Run First Backup (Optional)

```bash
# Trigger a manual backup immediately
sudo ./pbs-backup-manage.sh run rpool
```

## Management Commands

| Command | Description |
| --------- | ------------- |
| `install <profile>` | Create config files and systemd units for a new profile |
| `remove <profile>` | Stop timer, remove systemd units (preserves config) |
| `status [profile]` | Show status of one or all profiles |
| `test <profile>` | Test PBS server connectivity and authentication |
| `run <profile>` | Execute an immediate manual backup |
| `validate <profile>` | Validate config files, permissions, and schedule format |
| `list` | List all configured profiles with their status |
| `logs <profile>` | Show recent backup logs (journal + log file) |

## Configuration Reference

### Main Config (`<profile>.conf`)

| Key | Default | Description |
| ----- | --------- | ------------- |
| `PBS_SERVER` | — | PBS server hostname or IP (required) |
| `PBS_PORT` | `8007` | PBS API port |
| `PBS_DATASTORE` | — | Target datastore name (required) |
| `PBS_AUTH_ID` | — | Auth identity: `user@realm` or `user@realm!token` (required) |
| `PBS_FINGERPRINT` | — | SSL certificate fingerprint (recommended) |
| `BACKUP_PATHS` | — | Space-separated directories to back up (required) |
| `EXCLUDE_PATTERNS` | — | Space-separated glob patterns to exclude |
| `BACKUP_SCHEDULE` | `*-*-* 02:00:00` | Systemd `OnCalendar` schedule expression |
| `KEEP_LAST` | `3` | Keep N most recent backups |
| `KEEP_DAILY` | `7` | Keep daily backups for N days |
| `KEEP_WEEKLY` | `4` | Keep weekly backups for N weeks |
| `KEEP_MONTHLY` | `3` | Keep monthly backups for N months |
| `CHANGE_DETECTION_MODE` | `metadata` | `metadata` (fast) or `data` (thorough) |
| `SKIP_LOST_AND_FOUND` | `true` | Skip `lost+found` directories |
| `VERBOSE` | `false` | Enable verbose backup output |
| `LOCK_TIMEOUT` | `300` | Seconds to wait for lock before failing |
| `NOTIFY_ON_FAILURE` | — | Shell command to run on backup failure |

**⚠️ Mount Point Handling:**  
The script automatically detects mount points (including bind mounts) in `BACKUP_PATHS` and adds the `--include-dev` flag to traverse them. This ensures bind-mounted LXC container data directories (e.g., `/rpool/datastore/grafana`, `/rpool/datastore/influxdb`) are included in backups rather than skipped.

### Credentials File (`<profile>.credentials`)

| Key | Description |
| ----- | ------------- |
| `PBS_PASSWORD` | User password or API token secret |
| `ENCRYPTION_KEY` | Client-side encryption key (generated with `proxmox-backup-client key create`) |

**🔒 Client-Side Encryption (HIGHLY RECOMMENDED):**

Backups are **NOT encrypted by default** on PBS. Without encryption, anyone with access to PBS or backup files can read your data.

**Enable encryption** by setting `ENCRYPTION_KEY` in the credentials file:

```bash
# Generate a new encryption key
proxmox-backup-client key create /tmp/backup.key --kdf none

# Copy the key to credentials file
echo "ENCRYPTION_KEY=\"$(cat /tmp/backup.key)\"" >> /etc/pbs-backup/<profile>.credentials
rm /tmp/backup.key
```

**⚠️ CRITICAL WARNING:**

- Without the encryption key, **backup restoration is IMPOSSIBLE**
- Store a backup copy in a password manager, Vault, or secure offline location
- Loss of the key = permanent data loss

The `install` command offers to generate an encryption key automatically.

### Schedule Examples

| Schedule | `OnCalendar` Value |
| ---------- | ------------------- |
| Daily at 2:00 AM | `*-*-* 02:00:00` |
| Twice daily (2 AM, 2 PM) | `*-*-* 02,14:00:00` |
| Weekly on Sunday at 3 AM | `Sun *-*-* 03:00:00` |
| Every 6 hours | `*-*-* 00/6:00:00` |
| Monthly on 1st at midnight | `*-*-01 00:00:00` |

Validate any schedule with: `systemd-analyze calendar "<expression>"`

## Monitoring & Troubleshooting

```bash
# Check timer status and next run
systemctl list-timers 'pbs-backup-*'

# Check last backup result
systemctl status pbs-backup-rpool.service

# View real-time logs
journalctl -u pbs-backup-rpool.service -f

# View log file
tail -f /var/log/pbs-backup/rpool.log

# List backups on PBS server
export PBS_REPOSITORY="root@pam@192.0.2.181:8007:backups"
proxmox-backup-client snapshot list
```

### Exit Codes

| Code | Meaning |
| ----- | ------- |
| `0` | Success |
| `1` | Configuration error (missing file, bad permissions, invalid values) |
| `2` | Lock acquisition failed (another backup is running) |
| `3` | Backup execution failed |
| `4` | Prune (retention) execution failed |

---

## Architecture Design

```text
┌─────────────────────────────┐
│   pbs-backup-manage.sh      │  ← Management CLI (human interaction)
│   install/remove/status/... │
└─────────────┬───────────────┘
              │ creates
              ▼
┌─────────────────────────────┐
│   systemd timer + service   │  ← Scheduling (automated)
│   pbs-backup-<profile>.*    │
└─────────────┬───────────────┘
              │ invokes
              ▼
┌─────────────────────────────┐
│   pbs-backup.sh <profile>   │  ← Backup runner (non-interactive)
│   parse config → lock →     │
│   backup → prune → unlock   │
└─────────────┬───────────────┘
              │ reads
              ▼
┌─────────────────────────────┐
│   /etc/pbs-backup/          │  ← Configuration (root-only)
│   <profile>.conf            │
│   <profile>.credentials     │
└─────────────────────────────┘
```

## License

This project is provided as-is for homelab use. The script is MIT licensed.
