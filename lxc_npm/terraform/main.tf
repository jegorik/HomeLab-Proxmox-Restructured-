# =============================================================================
# Nginx Proxy Manager LXC Container - Main Terraform Configuration
# =============================================================================
# Deploys NPM in a Proxmox LXC container
#
# Last Updated: January 2026
# =============================================================================

# -----------------------------------------------------------------------------
# LXC Container Resource
# -----------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "lxc" {
  node_name   = var.pve_target_node
  vm_id       = var.container_id
  description = var.container_description

  tags = var.tags

  # Start behavior
  started       = var.container_start
  start_on_boot = var.container_onboot
  unprivileged  = var.container_unprivileged

  # Template
  operating_system {
    template_file_id = var.container_template
    type             = "debian"
  }

  # Initialization
  initialization {
    hostname = var.container_hostname

    ip_config {
      ipv4 {
        address = var.network_ip
        gateway = var.network_gateway
      }
    }

    dns {
      servers = [var.network_dns]
    }

    user_account {
      keys     = [var.ssh_public_key]
      password = random_password.root_password.result
    }
  }

  # Hardware - NPM requires more RAM for Node.js build
  cpu {
    cores = var.container_cores
  }

  memory {
    dedicated = var.container_memory
    swap      = var.container_swap
  }

  disk {
    datastore_id = var.container_storage
    size         = var.container_disk_size
  }

  # Network
  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  # Features for privileged operations if needed
  features {
    nesting = true
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account[0].password
    ]
  }
}

# -----------------------------------------------------------------------------
# Random Password for Root
# -----------------------------------------------------------------------------

resource "random_password" "root_password" {
  length           = 24
  special          = true
  override_special = "!@#$%^&*"
}

# -----------------------------------------------------------------------------
# Create Ansible User
# -----------------------------------------------------------------------------

resource "null_resource" "create_ansible_user" {
  depends_on = [proxmox_virtual_environment_container.lxc]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = split("/", var.network_ip)[0]
      user        = "root"
      private_key = file("~/.ssh/id_ed25519")
      timeout     = "5m"
    }

    inline = [
      "useradd -m -s /bin/bash ${var.ssh_user} || true",
      "echo '${var.ssh_user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${var.ssh_user}",
      "mkdir -p /home/${var.ssh_user}/.ssh",
      "echo '${var.ssh_public_key}' > /home/${var.ssh_user}/.ssh/authorized_keys",
      "chown -R ${var.ssh_user}:${var.ssh_user} /home/${var.ssh_user}/.ssh",
      "chmod 700 /home/${var.ssh_user}/.ssh",
      "chmod 600 /home/${var.ssh_user}/.ssh/authorized_keys"
    ]
  }
}
