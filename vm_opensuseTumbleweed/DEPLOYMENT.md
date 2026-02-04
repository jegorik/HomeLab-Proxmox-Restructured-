# OpenSUSE Tumbleweed VM - Deployment Guide

**Project**: vm_opensuseTumbleweed  
**Purpose**: OpenSUSE Tumbleweed workstation VM with desktop environment and USB passthrough  
**Status**: Production-ready with Vault integration  
**Last Updated**: February 2026

---

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Deployment Steps](#deployment-steps)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

---

## Overview

This guide provides step-by-step instructions for deploying an OpenSUSE Tumbleweed workstation VM on Proxmox VE using OpenTofu/Terraform and Ansible.

### What Gets Deployed

- **VM Configuration**: UEFI-based VM with 2 CPU cores, 4GB RAM, 32GB boot disk
- **Persistent Storage**: VirtIO-FS mounts for `/home` and `/persistent/etc` from host ZFS datasets
- **Network**: Static IP or DHCP configuration
- **USB Passthrough**: Up to 4 USB devices (keyboard, mouse, etc.)
- **Desktop Environment**: KDE Plasma or GNOME (configurable)
- **QEMU Guest Agent**: For Proxmox integration
- **Automation User**: Ansible user with SSH key authentication

### Data Persistence Model

This project uses **VirtIO-FS** to share host ZFS datasets with the VM, enabling:

- **User data survives VM destruction** - `/home` is mounted from host ZFS
- **Selective /etc persistence** - NetworkManager, systemd units persist via symlinks
- **Permission consistency** - Fixed UID 1000 ensures ownership matches across recreations
- **Fresh install vs reconnect** - Ansible detects existing data and handles accordingly

```text
Host ZFS Datasets                 VM Mount Points
─────────────────                 ───────────────
/<pool>/vm_workstation/home   →   /home (virtiofs)
/<pool>/vm_workstation/etc    →   /persistent/etc (virtiofs)
                                  ├── NetworkManager → /etc/NetworkManager (symlink)
                                  └── systemd/system → /etc/systemd/system (symlink)
```

### Deployment Time

- **Terraform Apply**: ~5-10 minutes (includes cloud image download)
- **Ansible Configuration**: ~10-15 minutes (includes desktop environment)
- **Total**: ~15-25 minutes

---

## Prerequisites

### 1. Infrastructure Requirements

✅ **Proxmox VE 8.4+** installed and accessible (VirtIO-FS support)  
✅ **HashiCorp Vault** deployed and configured (see [lxc_vault](../lxc_vault/README.md))  
✅ **Network bridge** (vmbr0) configured  
✅ **Storage** available for VM boot disk (local-lvm or other)  
✅ **ZFS pool** available for persistent data (see section 1.1)

### 1.1 ZFS Datasets for Persistent Storage (REQUIRED)

Create ZFS datasets on your Proxmox host for persistent VM data:

```bash
# SSH to Proxmox host
ssh root@<your-proxmox-host>

# Create parent dataset (adjust pool name to match your environment)
zfs create <your-pool>/vm_workstation

# Create home dataset for user data
zfs create <your-pool>/vm_workstation/home

# Create etc dataset for selective system configs
zfs create <your-pool>/vm_workstation/etc

# CRITICAL: Enable POSIX ACLs for virtiofs compatibility
# Without this, virtiofs mounts will fail with "Operation not supported" errors
zfs set acltype=posix <your-pool>/vm_workstation/home
zfs set acltype=posix <your-pool>/vm_workstation/etc

# Set ownership for VM user (UID 1000)
chown 1000:1000 /<your-pool>/vm_workstation/home

# Verify datasets and ACL configuration
zfs list | grep vm_workstation
zfs get acltype <your-pool>/vm_workstation/home
zfs get acltype <your-pool>/vm_workstation/etc
```

**Example with pool name `rpool`:**

```bash
zfs create rpool/datastore/vm_workstation
zfs create rpool/datastore/vm_workstation/home
zfs create rpool/datastore/vm_workstation/etc

# Enable POSIX ACLs (REQUIRED for virtiofs)
zfs set acltype=posix rpool/datastore/vm_workstation/home
zfs set acltype=posix rpool/datastore/vm_workstation/etc

chown 1000:1000 /rpool/datastore/vm_workstation/home
```

### 1.2 Proxmox Directory Mappings (REQUIRED)

Create Directory Mappings in Proxmox GUI for VirtIO-FS:

1. Open Proxmox Web UI
2. Navigate to: **Datacenter → Resource Mappings → Add → Directory**
3. Create two mappings:

| ID | Path | Nodes | Comment |
| ---- | ------ | ------- | ---------- |
| `workstation_home` | `/<your-pool>/vm_workstation/home` | `<your-node>` | VirtIO-FS /home mount |
| `workstation_etc` | `/<your-pool>/vm_workstation/etc` | `<your-node>` | VirtIO-FS /etc persistence |

**Screenshot reference:**

```text
Datacenter
└── Resource Mappings
    └── Directory
        ├── workstation_home (/<pool>/vm_workstation/home)
        └── workstation_etc (/<pool>/vm_workstation/etc)
```

> **Note:** The mapping IDs (`workstation_home`, `workstation_etc`) must match the values in `terraform.tfvars`.

### 2. Vault Configuration

Before deploying, ensure Vault has:

```bash
# 1. Transit engine enabled
vault secrets enable transit

# 2. Transit key created
vault write -f transit/keys/vm-opensuse-tumbleweed

# 3. Required secrets stored
vault kv put secret/proxmox/endpoint endpoint="https://192.168.1.100:8006"
vault kv put secret/proxmox/node node_name="pve"
vault kv put secret/proxmox/root username="root@pam"
vault kv put secret/ssh/root public_key="ssh-ed25519 AAAA..."
vault kv put secret/ssh/ansible public_key="ssh-ed25519 AAAA..."
vault kv put secret/aws/s3 bucket_name="your-terraform-state-bucket"

# 4. Ephemeral secrets (if using userpass auth)
# These are read dynamically during Terraform execution
```

### 3. Local Tools

Install required tools on your workstation:

```bash
# OpenTofu or Terraform
tofu version  # or: terraform version

# Ansible
ansible --version

# SSH client
ssh -V

# AWS CLI (for S3 backend)
aws --version
```

### 4. SSH Keys

Generate SSH keys if you haven't already:

```bash
# Root SSH key
ssh-keygen -t ed25519 -C "opensuse-vm-root" -f ~/.ssh/pve_ssh

# Ansible SSH key
ssh-keygen -t ed25519 -C "ansible@opensuse-vm" -f ~/.ssh/ansible

# Add public keys to Vault (see step 2 above)
```

---

## Deployment Steps

### Step 1: Prepare Configuration Files

```bash
# Navigate to project directory
cd /path/to/HomeLab(Proxmox)/vm_opensuseTumbleweed/terraform

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars

# Create S3 backend configuration
cp s3.backend.config.template s3.backend.config

# Edit terraform.tfvars
vim terraform.tfvars
```

**Key Variables to Configure**:

```hcl
# VM Identity
vm_id = 400                              # Unique VM ID
vm_hostname = "opensuseTumbleweed-vm"    # VM hostname
vm_ip_address = "192.168.0.210/24"       # Static IP with CIDR
vm_gateway = "192.168.0.1"               # Default gateway

# Resources
vm_cpu_cores = 2                         # CPU cores
vm_memory_dedicated = 4096               # RAM in MB
vm_boot_disk_size = 32                   # Boot disk in GB

# VirtIO-FS Persistent Storage (must match Proxmox Directory Mappings)
virtiofs_home_enabled = true
virtiofs_home_mapping = "workstation_home"  # Proxmox mapping ID for /home
virtiofs_etc_enabled = true
virtiofs_etc_mapping = "workstation_etc"    # Proxmox mapping ID for /persistent/etc
target_user_uid = 1000                      # Fixed UID (must match ZFS ownership)

# Vault Configuration
vault_address = "http://192.168.1.50:8200"
transit_key_name = "vm-opensuse-tumbleweed"

# USB Passthrough (find devices with 'lsusb' on Proxmox host)
vm_usb_device_1_host = "212e:1534"       # Keyboard (vendor:product)
vm_usb_device_2_host = "1-4"             # Mouse (hub-port)
vm_usb_device_3_host = "4-2.4"           # Additional device
vm_usb_device_4_host = "046d:c328"       # Another device

# Cloud Image
cloud_image_download = true              # Download cloud image automatically
vm_create_new = true                     # Create new VM (not manage existing)
```

**Edit S3 Backend Configuration**:

```bash
vim s3.backend.config
```

```hcl
bucket = "your-terraform-state-bucket"
key    = "vm_opensuseTumbleweed/terraform.tfstate"
region = "eu-central-1"
```

### Step 2: Initialize Terraform

```bash
# Initialize Terraform with S3 backend
tofu init -backend-config=s3.backend.config

# Verify initialization
tofu providers
```

**Expected Output**:

```text
Terraform has been successfully initialized!
```

### Step 3: Plan Infrastructure

```bash
# Review planned changes
tofu plan

# Save plan to file (optional)
tofu plan -out=tfplan
```

**Review the plan carefully**:

- ✅ VM will be created with specified resources
- ✅ Cloud image will be downloaded
- ✅ NetBox registration (if configured)
- ✅ No unexpected deletions or modifications

### Step 4: Apply Infrastructure

```bash
# Apply Terraform configuration
tofu apply

# Or apply saved plan
tofu apply tfplan
```

**During Apply**:

1. Cloud image downloads to Proxmox (~500MB, 2-5 minutes)
2. VM is created with UEFI configuration
3. Cloud-init configures network and users
4. VM starts automatically
5. Wait for SSH to become available (~2-3 minutes)

**Expected Output**:

```text
Apply complete! Resources: X added, 0 changed, 0 destroyed.

Outputs:

vm_id = 400
vm_ip_address = "192.168.0.210"
vm_hostname = "opensuseTumbleweed-vm"
ssh_command = "ssh ansible@192.168.0.210"
```

### Step 5: Verify VM is Running

```bash
# Check VM status in Terraform
tofu output

# Test SSH connectivity
ssh ansible@192.168.0.210

# Or check in Proxmox web UI
# Navigate to: Datacenter → Node → VM 400
```

### Step 6: Prepare Ansible Inventory

```bash
# Navigate to Ansible directory
cd ../ansible

# Create inventory from example
cp inventory.yml.example inventory.yml

# Edit inventory with VM IP
vim inventory.yml
```

**Update inventory.yml**:

```yaml
all:
  children:
    opensuse_vms:
      hosts:
        opensuse-workstation:
          ansible_host: 192.168.0.210  # Use your VM IP
          ansible_user: ansible
          ansible_ssh_private_key_file: ~/.ssh/ansible
      vars:
        ansible_become: true
```

### Step 7: Test Ansible Connectivity

```bash
# Test connection to VM
ansible all -m ping

# Expected output:
# opensuse-workstation | SUCCESS => {
#     "changed": false,
#     "ping": "pong"
# }
```

**If ping fails**:

1. Verify VM is running: `tofu output vm_ip_address`
2. Check SSH key: `ssh ansible@<vm-ip>`
3. Verify inventory.yml has correct IP and SSH key path

### Step 8: Deploy Ansible Configuration

```bash
# Run full playbook
ansible-playbook site.yml

# Or run specific roles
ansible-playbook site.yml --tags common
ansible-playbook site.yml --tags software_installation
ansible-playbook site.yml --tags desktop_environment
```

**Ansible Playbook Tasks**:

1. **Common Role**: Base system configuration, SSH hardening, firewall
2. **Software Installation**: Development tools, utilities, applications
3. **Desktop Environment**: KDE Plasma or GNOME installation

**Deployment Time**: ~10-15 minutes

**Expected Output**:

```text
PLAY RECAP *************************************************************
opensuse-workstation : ok=XX   changed=YY   unreachable=0    failed=0
```

### Step 9: Verify Deployment

```bash
# SSH into VM
ssh ansible@192.168.0.210

# Check system information
cat /etc/os-release
uname -a

# Check desktop environment
systemctl status display-manager

# Check USB devices (if passthrough configured)
lsusb

# Exit SSH
exit
```

---

## Post-Deployment Configuration

### 1. Access Desktop Environment

**Via Proxmox Console**:

1. Navigate to Proxmox web UI
2. Select VM 400 (opensuseTumbleweed-vm)
3. Click "Console"
4. Log in with user credentials

**Via Remote Desktop** (if configured):

```bash
# Install and configure VNC or RDP server in Ansible roles
```

### 2. Verify Persistent Storage

Verify VirtIO-FS mounts are active and persistent data is accessible:

```bash
# SSH into VM
ssh ansible@192.168.0.210

# Verify VirtIO-FS mounts
mount | grep virtiofs
# Should show:
# virtiofs_home on /home type virtiofs (rw,...)
# virtiofs_etc on /persistent/etc type virtiofs (rw,...)

# Verify home directory persistence
ls -la /home/

# Verify /etc symlinks
ls -la /etc/NetworkManager
ls -la /etc/systemd/system

# Check disk usage
df -h /home /persistent/etc
```

**Note:** User data in `/home` and selective `/etc` configs persist across VM recreations via host ZFS datasets. No additional disk configuration needed.

### 3. Install Additional Software

```bash
# Update package repositories
sudo zypper refresh

# Install additional packages
sudo zypper install <package-name>

# Example: Development tools
sudo zypper install git vim docker
```

### 4. Configure Firewall

```bash
# Check firewall status
sudo firewall-cmd --state

# Add service to firewall
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload

# List allowed services
sudo firewall-cmd --list-all
```

---

## Verification

### Infrastructure Verification

```bash
# Check Terraform state
tofu state list

# Verify VM in Proxmox
tofu output vm_id
# Then check in Proxmox UI: VM 400

# Verify NetBox registration (if configured)
# Check NetBox UI: Virtual Machines → opensuseTumbleweed-vm
```

### System Verification

```bash
# SSH into VM
ssh ansible@192.168.0.210

# 1. Check system information
cat /etc/os-release
# Expected: OpenSUSE Tumbleweed

# 2. Check network configuration
ip addr show
ip route show

# 3. Check disk configuration
lsblk
df -h

# 4. Check USB devices (if passthrough configured)
lsusb

# 5. Check QEMU Guest Agent
sudo systemctl status qemu-guest-agent

# 6. Check desktop environment
systemctl status display-manager

# 7. Check firewall
sudo firewall-cmd --state
```

### Ansible Verification

```bash
# Re-run Ansible playbook (should show no changes)
ansible-playbook site.yml --check

# Verify specific role
ansible-playbook site.yml --tags common --check
```

---

## Troubleshooting

### Issue: VM Won't Start

**Symptoms**: VM fails to start or boot

**Diagnosis**:

```bash
# Check VM status in Terraform
tofu output

# Check Proxmox logs
# In Proxmox UI: VM → Summary → Show Logs
```

**Solutions**:

1. Verify BIOS is set to `ovmf` (UEFI)
2. Check boot order includes `scsi0`
3. Verify cloud image downloaded successfully
4. Check Proxmox host has sufficient resources

### Issue: Cloud-Init Fails

**Symptoms**: VM starts but network/users not configured

**Diagnosis**:

```bash
# SSH into VM (if possible)
ssh ansible@<vm-ip>

# Check cloud-init logs
sudo cloud-init status
sudo journalctl -u cloud-init
```

**Solutions**:

1. Verify cloud-init configuration in terraform
2. Check network settings (IP, gateway, DNS)
3. Verify SSH public keys in Vault
4. Re-run cloud-init: `sudo cloud-init clean && sudo reboot`

### Issue: USB Devices Not Working

**Symptoms**: USB devices not detected in VM

**Diagnosis**:

```bash
# On Proxmox host
lsusb

# In VM
lsusb
```

**Solutions**:

1. Verify USB device ID format (vendor:product or hub-port)
2. Check device is not in use by Proxmox host
3. Try different USB port or format
4. Verify USB 3.0 setting matches device capabilities
5. Check VM configuration: `qm config <vmid>`

### Issue: Ansible Playbook Fails

**Symptoms**: Ansible playbook execution fails

**Diagnosis**:

```bash
# Test connectivity
ansible all -m ping

# Run playbook with verbose output
ansible-playbook site.yml -vvv
```

**Solutions**:

1. Verify SSH connectivity and key authentication
2. Check Ansible user has sudo access
3. Ensure python3-zypp is installed (pre-task)
4. Review specific task error messages
5. Run playbook with `--start-at-task` to skip completed tasks

### Issue: VirtioFS Mount "Operation not supported" Errors

**Symptoms**: Cannot write to `/home` or `/persistent/etc`, errors like:

- `mkdir: cannot create directory '/home': Operation not supported`
- `touch: cannot touch '/home/test': Operation not supported`
- Cloud-init fails with `[Errno 95] Operation not supported`

**Diagnosis**:

```bash
# SSH into VM as root
ssh root@<vm-ip>

# Test write to virtiofs mount
touch /home/test_write

# Check mount status
mount | grep virtiofs
df -h /home

# On Proxmox host - check ZFS ACL configuration
ssh root@<proxmox-host>
zfs get acltype <pool>/vm_workstation/home
```

**Root Cause**: ZFS dataset has `acltype=off` while virtiofs is configured with `expose-acl=1`. This mismatch causes EOPNOTSUPP (errno 95) errors.

**Solution**:

```bash
# On Proxmox host - enable POSIX ACLs on ZFS datasets
ssh root@<proxmox-host>

zfs set acltype=posix <pool>/vm_workstation/home
zfs set acltype=posix <pool>/vm_workstation/etc

# Verify configuration
zfs get acltype <pool>/vm_workstation/home
zfs get acltype <pool>/vm_workstation/etc

# Test write from VM (should now work)
ssh root@<vm-ip> "touch /home/test_write && echo 'Success!' && rm /home/test_write"
```

**Prevention**: Always set `acltype=posix` when creating ZFS datasets for virtiofs (see [Prerequisites](#prerequisites) section).

### Issue: Desktop Environment Not Starting

**Symptoms**: Desktop environment fails to start

**Diagnosis**:

```bash
# Check display manager status
sudo systemctl status display-manager

# Check X server logs
sudo journalctl -u display-manager
```

**Solutions**:

1. Verify desktop environment role completed successfully
2. Check graphics driver installation
3. Review Ansible playbook logs
4. Manually start display manager: `sudo systemctl start display-manager`

---

## Maintenance

### Regular Updates

```bash
# Update system packages
sudo zypper refresh
sudo zypper update

# Update specific package
sudo zypper update <package-name>

# Reboot if kernel updated
sudo reboot
```

### Backup Strategy

**Proxmox Snapshots**:

```bash
# Create snapshot
qm snapshot <vmid> <snapshot-name>

# List snapshots
qm listsnapshot <vmid>

# Restore snapshot
qm rollback <vmid> <snapshot-name>
```

**Proxmox Backup**:

```bash
# Backup VM
vzdump <vmid> --mode snapshot --storage <backup-storage>
```

### Monitoring

**QEMU Guest Agent Metrics**:

- Available in Proxmox web UI
- Shows CPU, memory, disk, network usage
- Enables graceful shutdown

**System Monitoring**:

```bash
# Check system status
systemctl status

# Monitor resources
htop

# Check disk usage
df -h

# Check network
ip addr show
```

### Scaling Resources

**Increase CPU/RAM**:

```bash
# Update terraform.tfvars
vm_cpu_cores = 4
vm_memory_dedicated = 8192

# Apply changes
tofu apply

# Reboot VM for changes to take effect
```

**Expand Disks**:

```bash
# Update terraform.tfvars
vm_boot_disk_size = 64
data_disk_size = 100

# Apply changes
tofu apply

# Resize filesystem in VM
sudo resize2fs /dev/sda1  # Boot disk
sudo resize2fs /dev/sdb   # Data disk
```

---

## Additional Resources

- [OpenSUSE Tumbleweed Documentation](https://doc.opensuse.org/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [QEMU Guest Agent](https://pve.proxmox.com/wiki/Qemu-guest-agent)
- [USB Passthrough Guide](https://pve.proxmox.com/wiki/USB_Devices_in_Virtual_Machines)

---

**Need Help?**

- Check [README.md](README.md) for project overview
- Review [Troubleshooting](#troubleshooting) section above
- Check Proxmox and Ansible logs for detailed error messages
- Verify all prerequisites are met

---

**Last Updated**: February 2026
