# =============================================================================
# LXC Semaphore UI - Main Terraform Configuration
# =============================================================================
# Deploys Semaphore UI Automation Platform in an LXC container on Proxmox
#
# Last Updated: January 2026
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  # Container tags as comma-separated string
  tags = join(",", var.lxc_tags)

  # Extract IP address without CIDR notation for SSH connection
  container_ip = var.lxc_ip_address == "dhcp" ? "" : split("/", var.lxc_ip_address)[0]

  # Extract Proxmox host from endpoint URL
  proxmox_host = regex("https://([^:]+):", data.vault_generic_secret.proxmox_endpoint.data["url"])[0]
}

# -----------------------------------------------------------------------------
# Password Generation
# -----------------------------------------------------------------------------

# Generate secure root password
resource "random_password" "root_password" {
  length           = var.password_length
  special          = true
  override_special = var.password_special_chars
  min_lower        = var.password_lower_chars_count
  min_upper        = var.password_upper_chars_count
  min_numeric      = var.password_numeric_count
  min_special      = var.password_special_chars_count
}

# Password lifecycle: Generate once and don't rotate on every apply
resource "terraform_data" "password_keeper" {
  input = random_password.root_password.result
}

# -----------------------------------------------------------------------------
# Bind Mount Permission Fix (Unprivileged Container Support)
# -----------------------------------------------------------------------------

# Fix bind mount permissions on Proxmox host for unprivileged container
# Unprivileged containers use UID mapping: container UID 900 → host UID 100900
resource "terraform_data" "fix_bind_mount_permissions" {
  # Upload permission fix script to Proxmox host
  provisioner "file" {
    source      = "${path.module}/../../lxc_base_template/scripts/fix_bind_mount_permissions.sh"
    destination = "/tmp/fix_bind_mount_permissions.sh"

    connection {
      type        = "ssh"
      user        = split("@", data.vault_generic_secret.proxmox_root.data["username"])[0]
      private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["key"]
      host        = local.proxmox_host
      timeout     = "2m"
    }
  }

  # Execute permission fix script on Proxmox host
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/fix_bind_mount_permissions.sh",
      "# Create and fix permissions for Semaphore data directory",
      "/tmp/fix_bind_mount_permissions.sh '${var.lxc_semaphore_data_mount_volume}' '${var.service_user_uid}' '${var.service_user_gid}'",
      "rm -f /tmp/fix_bind_mount_permissions.sh"
    ]

    connection {
      type        = "ssh"
      user        = split("@", data.vault_generic_secret.proxmox_root.data["username"])[0]
      private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["key"]
      host        = local.proxmox_host
      timeout     = "2m"
    }
  }
}

# -----------------------------------------------------------------------------
# LXC Container Resource
# -----------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "semaphore" {
  # Basic identification
  description = var.lxc_description
  node_name   = data.vault_generic_secret.proxmox_node_name.data["node_name"]
  vm_id       = var.lxc_id
  tags        = var.lxc_tags

  # Lifecycle settings
  start_on_boot = var.lxc_start_on_boot
  started       = var.lxc_started
  unprivileged  = var.lxc_unprivileged
  protection    = var.lxc_protection

  # Container features
  features {
    nesting = var.lxc_nesting
  }

  # Operating system template
  operating_system {
    template_file_id = "${var.lxc_template_storage}:vztmpl/${var.lxc_template_file}"
    type             = var.lxc_os_type
  }

  # Root filesystem
  disk {
    datastore_id = var.lxc_disk_storage
    size         = var.lxc_disk_size
  }

  # CPU allocation
  cpu {
    cores = var.lxc_cpu_cores
  }

  # Memory allocation
  memory {
    dedicated = var.lxc_memory
    swap      = var.lxc_swap
  }

  # Bind Mount for Semaphore Data Persistence
  mount_point {
    volume = var.lxc_semaphore_data_mount_volume
    path   = var.lxc_semaphore_data_mount_path
  }

  # Network configuration
  network_interface {
    name   = var.lxc_network_interface_name
    bridge = var.lxc_network_bridge
  }

  # Initialization settings
  initialization {
    hostname = var.lxc_hostname

    # IP configuration
    ip_config {
      ipv4 {
        address = var.lxc_ip_address == "dhcp" ? "dhcp" : var.lxc_ip_address
        gateway = var.lxc_ip_address == "dhcp" ? null : var.lxc_gateway
      }
    }

    # DNS configuration
    dns {
      servers = split(" ", var.lxc_dns_servers)
    }

    # User configuration - use SSH key from Vault
    user_account {
      keys     = [trimspace(data.vault_generic_secret.root_ssh_public_key.data["key"])]
      password = random_password.root_password.result
    }
  }

  # Startup/shutdown order
  startup {
    order      = var.lxc_startup_order
    up_delay   = var.lxc_up_delay
    down_delay = var.lxc_down_delay
  }

  # Ignore password changes after initial creation
  lifecycle {
    ignore_changes = [
      initialization[0].user_account[0].password
    ]
  }
}

# -----------------------------------------------------------------------------
# Ansible User Setup
# -----------------------------------------------------------------------------

# Create Ansible user with SSH access for configuration management
# This is a prerequisite for Ansible playbooks to work
resource "terraform_data" "ansible_user_setup" {
  # Trigger user creation only when container is recreated
  triggers_replace = [
    proxmox_virtual_environment_container.semaphore.id,
  ]

  # Ensure container is fully created before user setup
  depends_on = [proxmox_virtual_environment_container.semaphore]

  # Create Ansible user via SSH
  # Upload setup script
  provisioner "file" {
    source      = "${path.module}/../scripts/setup_ansible_user.sh"
    destination = "/tmp/setup_ansible_user.sh"

    connection {
      type        = "ssh"
      user        = split("@", data.vault_generic_secret.proxmox_root.data["username"])[0]
      private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["key"]
      host        = local.container_ip
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
      host        = local.container_ip
      timeout     = "5m"
    }
  }

  # SSH connection configuration
  connection {
    type        = "ssh"
    user        = split("@", data.vault_generic_secret.proxmox_root.data["username"])[0]
    private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["key"]
    host        = local.container_ip
    timeout     = "5m"
  }
}
