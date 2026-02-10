# System Package Update Playbook

Ansible playbook for automated package updates across Proxmox VMs and LXC containers. Supports Debian/Ubuntu (apt), RHEL/CentOS/Fedora/Rocky (dnf/yum), and OpenSUSE Leap/Tumbleweed (zypper).

## Features

| Feature | Description |
| --------- | ------------- |
| Multi-OS support | Debian, Ubuntu, RHEL, CentOS, Fedora, Rocky, OpenSUSE Leap/Tumbleweed, SLES |
| LXC awareness | Detects containers, skips reboot (warns instead) |
| Security-only mode | Apply only security patches (`-e only_security_updates=true`) |
| Disk space check | Fails early if insufficient space on `/` or `/var` |
| Error handling | `block/rescue` per OS family — one host failure doesn't stop others |
| Audit logging | OS-agnostic logs on each target with automatic rotation |
| Idempotent cleanup | Runs autoremove/autoclean only when `clean_packages=true` |
| Check mode | Full `--check` dry-run support |

## Prerequisites

- **Ansible** >= 2.15 on the control node
- **SSH key** access to all targets as `ansible` user
- **Python 3** on all target hosts
- **sudo** privileges for the `ansible` user (passwordless)
- Targets must have network access to their package repositories

## Quick Start

```bash
cd ansible_base_scripts/vms_packages_update

# 1. Create inventory
cp inventory.yml.example inventory.yml
# Edit inventory.yml — update IP addresses

# 2. Test connectivity
ansible -i inventory.yml all -m ping

# 3. Dry run (safe — no changes)
ansible-playbook -i inventory.yml packages_update.yml --check

# 4. Apply updates
ansible-playbook -i inventory.yml packages_update.yml
```

## Usage Examples

```bash
# Update all hosts
ansible-playbook -i inventory.yml packages_update.yml

# Update only LXC containers
ansible-playbook -i inventory.yml packages_update.yml -l containers

# Update only VMs with automatic reboot
ansible-playbook -i inventory.yml packages_update.yml -l vms -e "reboot_enabled=true"

# Update a single host
ansible-playbook -i inventory.yml packages_update.yml -l grafana

# Security-only updates (all hosts)
ansible-playbook -i inventory.yml packages_update.yml -e "only_security_updates=true"

# Skip cleanup (faster, no autoremove)
ansible-playbook -i inventory.yml packages_update.yml -e "clean_packages=false"

# Run specific tags only
ansible-playbook -i inventory.yml packages_update.yml --tags update,debian
```

## Variables Reference

| Variable | Default | Description |
| --------- | --------- | ------------- |
| `reboot_enabled` | `false` | Enable automatic reboot after kernel updates. Only affects VMs — LXC containers always skip reboot. |
| `reboot_timeout` | `300` | Maximum seconds to wait for a host to come back after reboot |
| `clean_packages` | `true` | Run autoremove/autoclean after updates |
| `only_security_updates` | `false` | Apply only security patches (apt: `-security` release; dnf: `--security`; zypper: `patch --category security`) |
| `enable_update_logging` | `true` | Write audit logs to `/var/log/ansible-updates/` on each target |
| `log_directory` | `/var/log/ansible-updates` | Path for audit logs on target hosts |
| `log_retention_count` | `30` | Days to keep log files before cleanup |
| `disk_space_min_mb` | `500` | Minimum free space (MB) on `/` before proceeding |

All variables can be overridden via `-e` flag or in a variables file.

## Inventory Structure

The playbook uses group-based targeting. See `inventory.yml.example` for the full template.

```text
all
├── containers         # LXC — reboot skipped automatically
│   ├── vault          (192.168.1.109)
│   ├── netbox         (192.168.1.105)
│   ├── npm            (192.168.1.100)
│   ├── grafana        (192.168.1.106)
│   ├── influxdb       (192.168.1.200)
│   ├── pbs            (192.168.1.110)
│   └── semaphoreui    (192.168.1.100)
└── vms                # Full VMs — reboot supported
    ├── docker-pool    (192.168.1.200, Ubuntu)
    └── opensuse-tw    (192.168.1.XXX, Tumbleweed)
```

## Tags

| Tag | Scope |
| ----- | ------- |
| `pre-check` | Disk space check |
| `update` | Package update tasks |
| `cleanup` | Autoremove/autoclean |
| `reboot` | Reboot check and execution |
| `debian` | Debian/Ubuntu tasks |
| `redhat` | RHEL/CentOS/Fedora/Rocky tasks |
| `suse` | OpenSUSE/SLES tasks |
| `leap` | OpenSUSE Leap specific |
| `tumbleweed` | OpenSUSE Tumbleweed specific |

## LXC Container Reboot Limitation

`ansible.builtin.reboot` is **incompatible** with LXC containers — the module relies on systemd signaling that doesn't work properly in unprivileged containers.

The playbook detects LXC containers via `ansible_virtualization_type` and automatically:

- **Skips** the reboot task
- **Warns** that manual restart is needed

To restart a container from the Proxmox host:

```bash
pct reboot <VMID>
```

## OpenSUSE Zypper Compatibility

The `community.general.zypper` Ansible module uses `--xmlout` which breaks on Tumbleweed 2025+ due to the transaction backend prompt. All zypper operations use `ansible.builtin.command` as a workaround, consistent with the `vm_opensuseTumbleweed` project in this workspace.

## Audit Logging

When `enable_update_logging=true` (default), the playbook writes a structured log file on each target host:

```bash
/var/log/ansible-updates/update-2026-02-10.log
```

One file per day (overwrites on same-day re-runs). Files older than `log_retention_count` days are automatically removed. Logs include: OS info, update results, reboot status, and error details.

## SemaphoreUI Integration

To use this playbook with SemaphoreUI:

1. Add this repository as a **Project Repository** in Semaphore
2. Create an **Inventory** pointing to your `inventory.yml`
3. Create a **Task Template**:
   - Playbook: `ansible_base_scripts/vms_packages_update/packages_update.yml`
   - Arguments: (none for automatic mode, or add `--check` for dry-run)
   - Extra Variables: `reboot_enabled: false`
4. Schedule the task for your maintenance window

## Troubleshooting

| Problem | Solution |
| --------- | ---------- |
| `INSUFFICIENT DISK SPACE` | Free space on the target before running updates. Reduce `disk_space_min_mb` if the threshold is too high. |
| `apt cache update failed` | Check network connectivity and repository configuration on the target. |
| `needs-restarting: command not found` | The playbook auto-installs `dnf-utils` on RedHat systems. If yum-based, install `yum-utils` manually. |
| `zypper dup had conflicts` | Connect to the Tumbleweed host and run `zypper dup` interactively to resolve. |
| Reboot not happening on containers | This is by design. Use `pct reboot <VMID>` from Proxmox host. |
| Host unreachable after update | Check if the host is still booting. Increase `reboot_timeout` if needed. |

## File Structure

```text
ansible_base_scripts/vms_packages_update/
├── ansible.cfg              # Ansible configuration
├── inventory.yml.example    # Inventory template (copy to inventory.yml)
├── packages_update.yml      # Main playbook
└── README.md                # This file
```
