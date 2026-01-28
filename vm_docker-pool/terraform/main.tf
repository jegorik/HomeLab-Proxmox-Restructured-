# =============================================================================
# VM Docker Pool - Main Terraform Configuration
# =============================================================================
#
# This module provisions an Ubuntu Server 24.04.3 LTS VM on Proxmox VE with
# Docker, Docker Compose, and Portainer for container management.
#
# Features:
# - Cloud-init based initialization with SSH key authentication
# - Secure random password generation for backup access
# - TPM 2.0 support for enhanced security
# - QEMU Guest Agent for VM management and IP reporting
# - Q35 machine type with VirtIO drivers for optimal performance
# - Bind mount for Portainer data persistence
#
# Usage:
#   ./deploy.sh plan    # Dry-run
#   ./deploy.sh deploy  # Full deployment
#
# Security Notes:
# - SSH key authentication is preferred over password
# - Passwords are stored in Terraform state - ensure state encryption via Vault Transit
# - Portainer data persists in /rpool/datastore/portainer for redeployment safety
#
# Last Updated: January 2026
# =============================================================================


# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  # Extract IP address without CIDR notation for SSH connection
  vm_ip = var.vm_ip_address == "dhcp" ? "" : split("/", var.vm_ip_address)[0]
}

# -----------------------------------------------------------------------------
# Random Password Generation
# -----------------------------------------------------------------------------
# Generates a secure random password for the VM user account.
# Password is encrypted in state via Vault Transit engine.

resource "random_password" "vm_root_password" {
  length           = var.password_length
  special          = true
  override_special = var.password_special_chars
  min_lower        = var.password_lower_chars_count
  min_upper        = var.password_upper_chars_count
  min_numeric      = var.password_numeric_count
  min_special      = var.password_special_chars_count
}

# -----------------------------------------------------------------------------
# Password Keeper - Prevent Unintended Password Rotation
# -----------------------------------------------------------------------------
# This terraform_data resource ensures the password isn't regenerated on every
# apply by storing the password in the lifecycle ignore_changes block.

resource "terraform_data" "password_keeper" {
  input = random_password.vm_root_password.result

  lifecycle {
    ignore_changes = [input]
  }
}

# -----------------------------------------------------------------------------
# Ubuntu Cloud Image Download
# -----------------------------------------------------------------------------
# Downloads the official Ubuntu 24.04.3 LTS cloud image for VM provisioning.
# The image is cached on the Proxmox datastore for reuse across VMs.

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type        = var.image_download_content_type
  datastore_id        = var.vm_cloud_image_datastore
  node_name           = data.vault_generic_secret.proxmox_node_name.data["node_name"]
  url                 = var.vm_cloud_image_url
  file_name           = var.vm_cloud_image_filename
  overwrite           = false
  overwrite_unmanaged = true
}

# -----------------------------------------------------------------------------
# Ubuntu Server Virtual Machine
# -----------------------------------------------------------------------------
# Main VM resource with cloud-init configuration for Docker workloads.

resource "proxmox_virtual_environment_vm" "docker_pool" {
  name        = var.vm_hostname
  description = var.vm_description
  tags        = var.vm_tags
  node_name   = data.vault_generic_secret.proxmox_node_name.data["node_name"]
  vm_id       = var.vm_id

  # ---------------------------------------------------------------------------
  # QEMU Guest Agent Configuration
  # ---------------------------------------------------------------------------
  # Required for retrieving VM IP addresses and executing guest commands
  agent {
    enabled = true
    timeout = "2m"
  }

  # Gracefully stop VM before destroying to prevent data corruption
  stop_on_destroy = true

  # ---------------------------------------------------------------------------
  # Startup/Shutdown Behavior
  # ---------------------------------------------------------------------------
  startup {
    order      = var.vm_startup_order
    up_delay   = var.vm_startup_up_delay
    down_delay = var.vm_startup_down_delay
  }

  # ---------------------------------------------------------------------------
  # CPU Configuration
  # ---------------------------------------------------------------------------
  cpu {
    cores = var.vm_cpu_cores
    type  = var.vm_cpu_type
  }

  # Machine type (q35 recommended for modern guests with PCIe support)
  machine = var.vm_machine_type

  # ---------------------------------------------------------------------------
  # Memory Configuration
  # ---------------------------------------------------------------------------
  memory {
    dedicated = var.vm_memory
    floating  = var.vm_memory_floating
  }

  # ---------------------------------------------------------------------------
  # Boot Disk Configuration
  # ---------------------------------------------------------------------------
  # Disk imported from cloud image with SSD optimization
  disk {
    datastore_id = var.vm_disk_datastore
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = var.vm_disk_interface
    size         = var.vm_disk_size
    discard      = "on"
    ssd          = true
  }

  # ---------------------------------------------------------------------------
  # Cloud-Init Configuration
  # ---------------------------------------------------------------------------
  # First-boot provisioning with user account and network setup
  initialization {
    datastore_id = var.vm_disk_datastore

    ip_config {
      ipv4 {
        address = var.vm_ip_address
        gateway = var.vm_gateway
      }
    }

    dns {
      servers = var.vm_dns_servers
    }

    # User account with SSH key authentication (primary) and password (backup)
    user_account {
      keys     = [trimspace(data.vault_generic_secret.root_ssh_public_key.data["key"])]
      password = random_password.vm_root_password.result
      username = var.vm_username
    }
  }

  # ---------------------------------------------------------------------------
  # Network Configuration
  # ---------------------------------------------------------------------------
  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  # ---------------------------------------------------------------------------
  # Operating System Type
  # ---------------------------------------------------------------------------
  operating_system {
    type = "l26" # Linux 2.6+ kernel
  }

  # ---------------------------------------------------------------------------
  # TPM 2.0 for Security Features
  # ---------------------------------------------------------------------------
  tpm_state {
    datastore_id = var.vm_disk_datastore
    version      = "v2.0"
  }

  # ---------------------------------------------------------------------------
  # Serial Console for Debugging
  # ---------------------------------------------------------------------------
  serial_device {}

  # ---------------------------------------------------------------------------
  # Lifecycle Rules
  # ---------------------------------------------------------------------------
  lifecycle {
    # Ignore changes to SSH keys after initial creation
    ignore_changes = [
      initialization[0].user_account[0].keys,
    ]
  }

  depends_on = [
    proxmox_virtual_environment_download_file.ubuntu_cloud_image
  ]
}


# -----------------------------------------------------------------------------
# Ansible User Setup
# -----------------------------------------------------------------------------

# Create Ansible user with SSH access for configuration management
# This is a prerequisite for Ansible playbooks to work
resource "terraform_data" "ansible_user_setup" {
  # Trigger user creation only when container is recreated
  triggers_replace = [
    proxmox_virtual_environment_vm.docker_pool.id
  ]

  # Ensure container is fully created before user setup
  depends_on = [proxmox_virtual_environment_vm.docker_pool]

  # Create Ansible user via SSH
  # Upload setup script
  provisioner "file" {
    source      = "${path.module}/../scripts/setup_ansible_user.sh"
    destination = "/tmp/setup_ansible_user.sh"

    connection {
      type        = "ssh"
      user        = split("@", data.vault_generic_secret.proxmox_root.data["username"])[0]
      private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["key"]
      host        = local.vm_ip
      timeout     = "5m"
    }
  }

  # Execute setup script
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup_ansible_user.sh",
      "ANSIBLE_SSH_KEY='${data.vault_generic_secret.ansible_ssh_public_key.data["key"]}' /tmp/setup_ansible_user.sh '${var.ansible_user_enabled}' '${var.ansible_user_name}' '${var.ansible_user_shell}' '${var.ansible_user_sudo}' '${join(",", var.ansible_user_sudo_commands)}' '${join(",", var.ansible_user_groups)}'",
      "rm -f /tmp/setup_ansible_user.sh"
    ]

    connection {
      type        = "ssh"
      user        = split("@", data.vault_generic_secret.proxmox_root.data["username"])[0]
      private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["key"]
      host        = local.vm_ip
      timeout     = "5m"
    }
  }
}

# -----------------------------------------------------------------------------
# Fix Bind Mount Permissions for Portainer
# -----------------------------------------------------------------------------
# For VMs, Portainer runs as UID 1000 (default docker user).
# This provisioner creates the data directory on Proxmox host with correct ownership.
#
# Note: VMs don't use unprivileged UID mapping like LXC containers,
# so we just need to ensure the directory exists with proper permissions.

resource "terraform_data" "fix_bind_mount_permissions" {
  count = var.portainer_bind_mount_enabled ? 1 : 0

  triggers_replace = {
    vm_id             = var.vm_id
    bind_mount_source = var.portainer_bind_mount_source
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = local.vm_ip
      user        = split("@", data.vault_generic_secret.proxmox_root.data["username"])[0]
      private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["key"]
      timeout     = "5m"
    }

    inline = [
      "#!/bin/bash",
      "set -e",
      "# Create Portainer data directory if it doesn't exist",
      "PORTAINER_DIR='${var.portainer_bind_mount_source}'",
      "if [[ ! -d \"$PORTAINER_DIR\" ]]; then",
      "  echo \"Creating Portainer data directory: $PORTAINER_DIR\"",
      "  mkdir -p \"$PORTAINER_DIR\"",
      "  chmod 755 \"$PORTAINER_DIR\"",
      "  echo \"Directory created successfully\"",
      "else",
      "  echo \"Portainer data directory already exists: $PORTAINER_DIR\"",
      "fi",
      "echo \"Portainer bind mount setup complete\""
    ]
  }

  depends_on = [proxmox_virtual_environment_vm.docker_pool]
}

# -----------------------------------------------------------------------------
# Wait for VM to be Ready
# -----------------------------------------------------------------------------
# Ensures VM is fully booted and SSH is available before Ansible runs

resource "terraform_data" "wait_for_vm" {
  triggers_replace = {
    vm_id = proxmox_virtual_environment_vm.docker_pool.vm_id
  }

  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for VM to boot and SSH to become available..."
      VM_IP="${trimsuffix(var.vm_ip_address, "/24")}"
      
      # Wait up to 5 minutes for SSH
      for i in $(seq 1 60); do
        if nc -z -w 2 "$VM_IP" 22 2>/dev/null; then
          echo "SSH is available on $VM_IP"
          exit 0
        fi
        echo "Waiting for SSH... (attempt $i/60)"
        sleep 5
      done
      
      echo "ERROR: SSH did not become available within 5 minutes"
      exit 1
    EOF
  }

  depends_on = [
    proxmox_virtual_environment_vm.docker_pool,
    terraform_data.fix_bind_mount_permissions
  ]
}
