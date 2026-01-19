# =============================================================================
# Nginx Proxy Manager LXC Container - Main Terraform Configuration
# =============================================================================
# Deploys NPM in a Proxmox LXC container
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
# LXC Container Resource
# -----------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "npm" {
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
      keys     = [trimspace(data.vault_generic_secret.root_ssh_public_key.data["public_key"])]
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
# Create Ansible User
# -----------------------------------------------------------------------------

resource "null_resource" "create_ansible_user" {
  count = var.ansible_user_enabled ? 1 : 0

  depends_on = [proxmox_virtual_environment_container.npm]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = local.container_ip
      user        = "root"
      private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["private_key"]
      timeout     = "5m"
    }

    inline = [
      # Create ansible user
      "useradd -m -s ${var.ansible_user_shell} ${var.ansible_user_name} || true",

      # Configure sudo access
      var.ansible_user_sudo ? "echo '${var.ansible_user_name} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${var.ansible_user_name}" : "true",

      # Setup SSH directory
      "mkdir -p /home/${var.ansible_user_name}/.ssh",
      "echo '${trimspace(data.vault_generic_secret.ansible_ssh_public_key.data["public_key"])}' > /home/${var.ansible_user_name}/.ssh/authorized_keys",

      # Set permissions
      "chown -R ${var.ansible_user_name}:${var.ansible_user_name} /home/${var.ansible_user_name}/.ssh",
      "chmod 700 /home/${var.ansible_user_name}/.ssh",
      "chmod 600 /home/${var.ansible_user_name}/.ssh/authorized_keys"
    ]
  }
}
