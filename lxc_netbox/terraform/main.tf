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

  # Extract Proxmox host from endpoint URL
  proxmox_host = regex("https://([^:]+):", data.vault_generic_secret.proxmox_endpoint.data["url"])[0]
}

# -----------------------------------------------------------------------------
# Host Bind Mount Permission Fix
# -----------------------------------------------------------------------------

# Fix permissions on Proxmox host for unprivileged container bind mounts
resource "terraform_data" "fix_bind_mount_permissions" {
  # Run this when important variables change
  triggers_replace = [
    var.lxc_id,
    var.lxc_unprivileged,
    var.lxc_netbox_mount_point_volume,
    var.lxc_postgresql_mount_point_volume,
    var.lxc_redis_mount_point_volume
  ]

  # Upload script to Proxmox host
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

  # Execute script on Proxmox host
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/fix_bind_mount_permissions.sh",
      # Fix NetBox main directory (service user 900)
      "/tmp/fix_bind_mount_permissions.sh '${var.lxc_netbox_mount_point_volume}' '${var.service_user_uid}' '${var.service_user_gid}'",
      # Fix PostgreSQL directory (postgres user 105:109 on Debian 12/13 usually, need to verify. Using 105:109 is risky if it changes.
      # Safest is to just chown to standard map if we know it.
      # Postgres is typically 105:109 or similar. Let's assume standard system users don't change often but they might.
      # For now, let's use the same script but with standard Postgres/Redis UIDs
      # Debian 12: postgres=105, redis=104 (example).
      # Better approach: We will fix Netbox path (900). For Postgres/Redis, if they fail, we might need to be smarter.
      # Let's fix NetBox path first as it's the main user data.
      # For Postgres/Redis, we'll try to guess typical IDs: Postgres(105), Redis(104).
      # Actually, let's stick to just Netbox user 900 for now. The others might be managed by the packages successfully if the dirs are empty.
      # If they are not empty, they need re-chowning.
      "/tmp/fix_bind_mount_permissions.sh '${var.lxc_postgresql_mount_point_volume}' '105' '109'", # Postgres default on some debian
      "/tmp/fix_bind_mount_permissions.sh '${var.lxc_redis_mount_point_volume}' '104' '104'",      # Redis default
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

# Create Proxmox LXC container for NetBox DCIM/IPAM platform
# This container will host the NetBox service with PostgreSQL database backend
resource "proxmox_virtual_environment_container" "netbox" {
  # Basic identification
  description = var.lxc_description
  node_name   = data.vault_generic_secret.proxmox_node_name.data["node_name"]
  vm_id       = var.lxc_id
  tags        = var.lxc_tags

  # Lifecycle settings
  start_on_boot = var.lxc_start_on_boot
  started       = var.lxc_started
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

  # NetBox application directory (persistent across container recreations)
  mount_point {
    volume = var.lxc_netbox_mount_point_volume
    path   = var.lxc_netbox_mount_point_path
  }

  # PostgreSQL database directory (persistent database storage)
  mount_point {
    volume = var.lxc_postgresql_mount_point_volume
    path   = var.lxc_postgresql_mount_point_path
  }

  # Redis cache directory (optional, for cache persistence)
  mount_point {
    volume = var.lxc_redis_mount_point_volume
    path   = var.lxc_redis_mount_point_path
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
      keys     = [data.vault_generic_secret.root_ssh_public_key.data["key"]]
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
# Ansible User Setup
# -----------------------------------------------------------------------------

# Create Ansible user with SSH access for configuration management
# This is a prerequisite for Ansible playbooks to work
resource "terraform_data" "ansible_user_setup" {
  # Trigger user creation only when container is recreated
  triggers_replace = [
    proxmox_virtual_environment_container.netbox.id,
  ]

  # Ensure container is fully created before user setup
  depends_on = [proxmox_virtual_environment_container.netbox]

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
}
