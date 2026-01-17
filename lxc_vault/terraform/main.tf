# =============================================================================
# HashiCorp Vault LXC Container - Infrastructure as Code
# =============================================================================
#
# This Terraform configuration deploys a HashiCorp Vault instance in a
# Proxmox LXC container with automated installation and initialization.
#
# Components:
# - LXC container with Debian base
# - HashiCorp Vault installation via official repository
# - Systemd service configuration
# - File-based storage backend
# - HTTP listener (TLS disabled - should be fronted by reverse proxy)
#
# Security Considerations:
# - Container runs unprivileged by default
# - Vault runs as dedicated system user
# - Root password is randomly generated if not provided
# - SSH key-based authentication enforced
# - State file encryption enabled (see encryption.tf)
#
# Post-Deployment:
# 1. Retrieve initialization keys from container: /root/vault-keys.txt
# 2. Store unseal keys and root token securely (use a password manager)
# 3. Configure TLS (recommended: use reverse proxy like Nginx)
# 4. Enable audit logging
# 5. Configure authentication methods
#
# Author: HomeLab Infrastructure
# Last Updated: December 2025
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  # Use provided password or generated one
  root_password = var.lxc_root_password != "" ? var.lxc_root_password : random_password.root_password.result

  # Container tags as comma-separated string
  tags = join(",", var.lxc_tags)

  # Extract IP address without CIDR notation for SSH connection
  container_ip = var.lxc_ip_address == "dhcp" ? "" : split("/", var.lxc_ip_address)[0]

  # Use Vault secrets or fallback to variables
  netbox_token = trimspace(file(pathexpand(var.netbox_api_token)))
}

# -----------------------------------------------------------------------------
# Password Generation
# -----------------------------------------------------------------------------

# Generate secure root password if not provided via variable
# Password will be stored in encrypted state file and can be retrieved
# using: tofu output -raw lxc_root_password
resource "random_password" "root_password" {
  length           = var.password_length
  special          = true
  override_special = var.password_special_chars
  min_lower        = var.password_lower_chars_count
  min_upper        = var.password_upper_chars_count
  min_numeric      = var.password_upper_numeric_count
  min_special      = var.password_upper_special_chars_count
}

# Password lifecycle: Generate once and don't rotate on every apply
# This prevents breaking SSH access during infrastructure updates
resource "terraform_data" "password_keeper" {
  input = random_password.root_password.result
}

# -----------------------------------------------------------------------------
# LXC Container Resource
# -----------------------------------------------------------------------------

# Create Proxmox LXC container for HashiCorp Vault
# This container will host the Vault service with file-based storage backend
resource "proxmox_virtual_environment_container" "vault" {
  # Basic identification
  description = var.lxc_description
  node_name   = var.proxmox_node
  vm_id       = var.lxc_id
  tags        = var.lxc_tags

  # Lifecycle settings
  start_on_boot = var.lxc_start_on_boot
  started       = true
  unprivileged  = var.lxc_unprivileged # Run unprivileged for security
  protection    = var.lxc_protection   # Prevent accidental deletion

  # Container features
  features {
    nesting = var.lxc_nesting # Required for systemd and proper service management
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

  # Bind Mount Configuration
  # ------------------------
  # Bind mounts allow the container to access directories from the Proxmox host filesystem.
  # This is useful for sharing data, storing Vault data on ZFS, or using external storage.
  #
  # IMPORTANT: Bind mounts REQUIRE root@pam authentication with password
  # API tokens do NOT work for bind mount operations, even with full permissions.
  #
  # Why root@pam is required:
  # 1. Bind mounts require direct filesystem access on the Proxmox host
  # 2. The Proxmox API uses elevated privileges to modify host mount points
  # 3. API tokens cannot execute certain privileged operations (security limitation)
  # 4. The bpg/proxmox provider needs username/password for mount point operations
  #
  # Proxmox Documentation:
  # - Bind Mounts: https://pve.proxmox.com/wiki/Linux_Container#pct_mount_points
  # - Container Configuration: https://pve.proxmox.com/pve-docs/pct.conf.5.html
  #
  # Provider Documentation:
  # - https://github.com/bpg/terraform-provider-proxmox/issues/836
  #
  # Privileged vs Unprivileged Containers:
  # - Bind mounts work best with PRIVILEGED containers (lxc_unprivileged = false)
  # - Unprivileged containers use UID/GID mapping which can cause permission issues
  # - With unprivileged containers, you must configure /etc/subuid and /etc/subgid on host
  # - Privileged containers: root in container = root on host (simpler, less secure)
  # - For production: Use unprivileged + proper UID mapping, or mount via NFS/CIFS
  #
  # See: https://pve.proxmox.com/wiki/Unprivileged_LXC_containers
  mount_point {
    volume = var.lxc_mount_point_volume
    path   = var.lxc_mount_point_path
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

    # User account configuration
    user_account {
      password = local.root_password
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  # Startup/shutdown behavior
  startup {
    order      = var.lxc_startup_order
    up_delay   = var.lxc_up_delay
    down_delay = var.lxc_down_delay
  }

  # Prevent unnecessary recreation when password or SSH keys change
  # This ensures container stability during state refreshes
  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}

# -----------------------------------------------------------------------------
# Vault Installation and Configuration
# -----------------------------------------------------------------------------

# Install and configure HashiCorp Vault via remote-exec provisioner
# This resource uses terraform_data for better lifecycle management
# and idempotency compared to null_resource
resource "terraform_data" "ansible_user_setup" {
  # Trigger user creation only when container is recreated
  triggers_replace = [
    proxmox_virtual_environment_container.vault.id,
  ]

  # Ensure container is fully created before user setup
  depends_on = [proxmox_virtual_environment_container.vault]

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
      apt-get update -qq && apt-get upgrade -qq

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
${trimspace(file(pathexpand(var.ansible_ssh_public_key_path)))}
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
  private_key = file(pathexpand(var.ssh_private_key_path))
  host        = local.container_ip
  timeout     = "5m"
}
}
}

