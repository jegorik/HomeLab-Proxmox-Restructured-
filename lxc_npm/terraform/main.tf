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

  # Bind Mount Configuration for Data Persistence
  # ---------------------------------------------
  # NPM stores all user data (SSL certs, database, proxy configs) in /data
  # This bind mount ensures data survives container recreation.
  #
  # IMPORTANT: Requires privileged container (lxc_unprivileged = false)
  # Host directory must exist before container creation.
  mount_point {
    volume = var.lxc_npm_data_mount_volume
    path   = var.lxc_npm_data_mount_path
  }

  mount_point {
    volume = var.lxc_npm_letsencrypt_mount_volume
    path   = var.lxc_npm_letsencrypt_mount_path
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
    proxmox_virtual_environment_container.npm.id,
  ]

  # Ensure container is fully created before user setup
  depends_on = [proxmox_virtual_environment_container.npm]

  # Create Ansible user via SSH
  provisioner "remote-exec" {
    inline = [<<-EOT
      #!/bin/bash
      set -e  # Exit on any error

      echo "=== Setting up Ansible user ==="

      # Wait for container to fully boot
      echo "Waiting for system to be ready..."
      sleep 10

      # Update package lists
      apt-get update -qq

      # Install sudo if not present
      apt-get install -y -qq sudo

      ${var.ansible_user_enabled ? <<-ANSIBLE_USER
      echo ""
      echo "Creating Ansible user: ${var.ansible_user_name}"

      # Create Ansible user if it doesn't exist
      if ! id -u ${var.ansible_user_name} > /dev/null 2>&1; then
        useradd -m -s ${var.ansible_user_shell} ${var.ansible_user_name}
        echo "✓ User '${var.ansible_user_name}' created"
      else
        echo "✓ User '${var.ansible_user_name}' already exists"
      fi

      # Create .ssh directory and set permissions
      mkdir -p /home/${var.ansible_user_name}/.ssh
      chmod 700 /home/${var.ansible_user_name}/.ssh

      # Add SSH public key
      cat > /home/${var.ansible_user_name}/.ssh/authorized_keys <<'ANSIBLE_KEY_EOF'
${data.vault_generic_secret.ansible_ssh_public_key.data["key"]}
ANSIBLE_KEY_EOF

      chmod 600 /home/${var.ansible_user_name}/.ssh/authorized_keys
      chown -R ${var.ansible_user_name}:${var.ansible_user_name} /home/${var.ansible_user_name}/.ssh

      ${var.ansible_user_sudo ? <<-SUDO_CONFIG
      # Configure sudo access
      usermod -aG sudo ${var.ansible_user_name}
      mkdir -p /etc/sudoers.d

      ${length(var.ansible_user_sudo_commands) > 0 ? <<-LIMITED_SUDO
      # Limited sudo commands
      cat > /etc/sudoers.d/${var.ansible_user_name} <<'SUDOERS_EOF'
# Ansible user sudo configuration - managed by Terraform
${var.ansible_user_name} ALL=(ALL) NOPASSWD: ${join(", ", var.ansible_user_sudo_commands)}
SUDOERS_EOF
      LIMITED_SUDO
      : <<-FULL_SUDO
      # Full sudo access without password
      cat > /etc/sudoers.d/${var.ansible_user_name} <<'SUDOERS_EOF'
# Ansible user sudo configuration - managed by Terraform
${var.ansible_user_name} ALL=(ALL) NOPASSWD:ALL
SUDOERS_EOF
      FULL_SUDO
    }

      chmod 440 /etc/sudoers.d/${var.ansible_user_name}
      visudo -c -f /etc/sudoers.d/${var.ansible_user_name}
      echo "✓ Sudo access configured"
      SUDO_CONFIG
  : "# Sudo access not enabled"}

      # Add to additional groups
      ${length(var.ansible_user_groups) > 0 ? "usermod -aG ${join(",", var.ansible_user_groups)} ${var.ansible_user_name}" : ""}

      echo ""
      echo "✓ Ansible user '${var.ansible_user_name}' setup complete"
      echo "SSH access: ssh ${var.ansible_user_name}@${local.container_ip}"
      ANSIBLE_USER
: "# Ansible user creation disabled"}
    EOT
]

# SSH connection configuration
connection {
  type        = "ssh"
  user        = "root"
  private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["key"]
  host        = local.container_ip
  timeout     = "5m"
}
}
}
