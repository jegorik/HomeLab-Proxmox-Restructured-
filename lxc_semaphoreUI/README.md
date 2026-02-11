# LXC Semaphore UI Project

## Overview

This project deploys [Semaphore UI](https://semaphoreui.com/), a modern UI for Ansible, Terraform, and other DevOps tools, within an unprivileged LXC container on Proxmox.

## Features

- **Base OS**: Debian (via LXC template)
- **Application**: Semaphore UI (installed via official .deb)
- **Database**: BoltDB (embedded, requires no external database service)
- **Configuration**: Managed via Ansible
- **Security**:
  - Unprivileged container
  - Service runs as dedicated user `semaphore` (UID 900)
  - Data persisted via bind mount to host ZFS pool

## Infrastructure

- **Terraform/OpenTofu**: Provisions the LXC container.
  - VMID: `108`
  - IP: `192.0.2.100/24`
  - RAM: `2048 MB`
  - Access: SSH Key (Root), Passwordless Sudo (Ansible User)
- **Ansible**: Configures the software.
  - Uses `semaphore` role to install and configure the service.
  - Generates `config.json` with secure random secrets for cookies/encryption.
  - Sets up Systemd service `semaphore.service`.

## Usage

### Deployment

1. **Provision Container**:

   ```bash
   cd terraform
   tofu init
   tofu apply
   ```

2. **Configure Service**:

   ```bash
   cd ../scripts
   # Ensure VAULT_TOKEN is set
   export SEMAPHORE_ADMIN_PASSWORD="your-strong-password"
   ./deploy.sh
   # Or manually: ./ansible.sh
   ```

### Access

- **Web UI**: <http://192.0.2.100:3000>
- **Default Admin User**: `admin` (password set during deployment)

## Data Persistence

Data is stored in `/var/lib/semaphore` inside the container, which is bind-mounted to `/rpool/data/semaphore` on the Proxmox host. This ensures data survives container recreation.

## Maintenance

- **Upgrades**: Rerun the Ansible playbook. It fetches the latest release from GitHub.
- **Backup**: Backup the host directory `/rpool/data/semaphore`.
