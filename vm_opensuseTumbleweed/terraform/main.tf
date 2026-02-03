# =============================================================================
# VM OpenSUSE Tumbleweed - Main Terraform Configuration
# =============================================================================

locals {
  # Extract IP address without CIDR notation for SSH connection
  vm_ip = var.vm_ip_address == "dhcp" ? "" : split("/", var.vm_ip_address)[0]
}

# -----------------------------------------------------------------------------
# Random Password Generation
# -----------------------------------------------------------------------------

resource "random_password" "vm_root_password" {
  length           = var.password_length
  special          = var.password_use_special_chars
  override_special = var.password_special_chars
  min_lower        = var.password_lower_chars_count
  min_upper        = var.password_upper_chars_count
  min_numeric      = var.password_numeric_count
  min_special      = var.password_special_chars_count
}

resource "terraform_data" "password_keeper" {
  input = random_password.vm_root_password.result
  lifecycle {
    ignore_changes = [input]
  }
}

# -----------------------------------------------------------------------------
# OpenSUSE Tumbleweed Virtual Machine Workstation
# -----------------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "tumbleweed_vm" {
  count = var.vm_create_new ? 1 : 0

  # -----------------------------------------------------------------------------
  # VM Identity and Lifecycle
  # -----------------------------------------------------------------------------

  name        = var.vm_hostname
  description = var.vm_description
  tags        = var.vm_tags
  node_name   = data.vault_generic_secret.proxmox_node_name.data["node_name"]
  vm_id       = var.vm_id

  # Start VM automatically when Proxmox host boots
  on_boot = var.vm_on_boot

  # VM lifecycle options
  started             = var.vm_started
  stop_on_destroy     = var.vm_stop_on_destroy
  template            = var.vm_template
  migrate             = var.vm_migrate
  reboot              = var.vm_reboot
  protection          = var.vm_protection
  reboot_after_update = var.vm_reboot_after_update

  # The QEMU agent configuration
  agent {
    enabled = var.vm_qemu_agent_enabled
    timeout = var.vm_qemu_agent_timeout
    trim    = var.vm_qemu_agent_trim
    type    = var.vm_qemu_agent_type
  }

  # -------------------------------------------------------------------------
  # VM Startup Configuration
  # -------------------------------------------------------------------------

  startup {
    order      = var.vm_startup_order
    up_delay   = var.vm_startup_up_delay
    down_delay = var.vm_startup_down_delay
  }

  # -------------------------------------------------------------------------
  # Lifecycle Management Configuration
  # -------------------------------------------------------------------------
  # Controls how Terraform manages VM lifecycle and state changes
  #
  # prevent_destroy: Prevents accidental deletion of the VM
  #   Use case: Production VMs that should never be deleted via Terraform
  #   Warning: Must be commented out to destroy the VM
  #
  # ignore_changes: Ignores specific attribute changes to prevent unnecessary updates
  #   Common scenarios:
  #   - MAC addresses may change on reboot or network reconfiguration
  #   - Disk size changes made manually in Proxmox GUI
  #   - Tags modified outside Terraform
  #
  # Example: Ignore all disk size changes to prevent resize errors
  #   ignore_changes = [disk[0].size]
  #
  # Example: Ignore multiple attributes
  #   ignore_changes = [network_device[0].mac_address, tags, description]

  lifecycle {
    # Uncomment to prevent VM destruction via tofu destroy
    # prevent_destroy = true

    # Uncomment to ignore specific attribute changes
    # ignore_changes = [
    #   # Ignore MAC address changes (can vary after reboot)
    #   network_device[0].mac_address,
    #   # Ignore disk size changes (prevents resize errors)
    #   disk[0].size,
    # ]
  }

  # -------------------------------------------------------------------------
  # BIOS and Machine Type
  # -------------------------------------------------------------------------

  bios    = var.vm_bios # Use OVMF for UEFI support (OpenSUSE Tumbleweed requirement)
  machine = var.vm_machine_type

  # -------------------------------------------------------------------------
  # Boot Configuration
  # -------------------------------------------------------------------------

  boot_order = var.vm_boot_order

  # -------------------------------------------------------------------------
  # CPU Configuration
  # -------------------------------------------------------------------------
  # High-performance CPU configuration with host passthrough for maximum performance
  #
  # CPU Type Options:
  # - "host": Maximum performance, exposes all host CPU features to guest
  #   Best for: Gaming, GPU workloads, development environments
  #   Limitation: Less portable across different CPU architectures
  #
  # - "x86-64-v2-AES": Portable baseline with AES-NI support
  #   Best for: General purpose VMs that may migrate between hosts
  #   Features: SSE4.2, AVX, AES-NI encryption
  #
  # - "kvm64": Generic x86-64 (most compatible, lowest performance)
  #   Best for: Maximum compatibility across different hardware
  #
  # Performance Tips:
  # - Set cores to match physical cores (avoid overcommit for workstation VMs)
  # - Enable NUMA if host has multiple CPU sockets
  # - Use cpu_units to prioritize CPU scheduling (higher = more priority)
  # - Consider Hyper-V enlightenments for Windows guests (via kvm_arguments)

  cpu {
    cores        = var.vm_cpu_cores
    sockets      = var.vm_cpu_sockets
    type         = var.vm_cpu_type
    architecture = var.vm_cpu_architecture
    hotplugged   = var.vm_cpu_hotplugged
    limit        = var.vm_cpu_limit
    units        = var.vm_cpu_units
    numa         = var.vm_cpu_numa
  }

  # -------------------------------------------------------------------------
  # Memory Configuration
  # -------------------------------------------------------------------------
  # Dedicated memory with ballooning support

  memory {
    dedicated      = var.vm_memory_dedicated
    floating       = var.vm_memory_floating
    keep_hugepages = var.vm_memory_keep_hugepages
  }

  # -------------------------------------------------------------------------
  # EFI Disk (Required for OVMF/UEFI)
  # -------------------------------------------------------------------------

  efi_disk {
    datastore_id = var.vm_disk_datastore
    file_format  = var.vm_efi_disk_file_format # raw format required for some storages, generally faster
    type         = var.vm_efi_disk_type        # standard EFI disk size
  }

  # -------------------------------------------------------------------------
  # Boot Disk (Imported from Cloud Image)
  # -------------------------------------------------------------------------
  # High-performance disk configuration with ssd=true (discard) and iothread
  # cache=writeback is default on Proxmox for performance, but can be set if needed

  disk {
    datastore_id = var.vm_disk_datastore
    interface    = var.vm_disk_interface
    file_id      = var.vm_create_new && var.cloud_image_download ? proxmox_virtual_environment_download_file.tumbleweed_cloud_image.id : null
    size         = var.vm_boot_disk_size
    aio          = var.vm_disk_aio
    cache        = var.vm_disk_cache
    discard      = var.vm_disk_discard
    ssd          = var.vm_disk_ssd
    iothread     = var.vm_disk_iothread

    # Backup and replication
    backup    = var.vm_disk_backup
    replicate = var.vm_disk_replicate
  }

  # -------------------------------------------------------------------------
  # Secondary Data Disk (Persistence)
  # -------------------------------------------------------------------------
  # Dedicated disk for /data or /home to survive re-provisioning of boot disk

  disk {
    datastore_id = var.data_disk_datastore
    interface    = var.data_disk_interface # Extracted to variable
    size         = var.data_disk_size
    file_format  = var.data_disk_file_format
    aio          = var.data_disk_aio
    cache        = var.data_disk_cache
    discard      = var.data_disk_discard
    ssd          = var.data_disk_ssd
    iothread     = var.data_disk_iothread

    # Backup and replication
    backup    = var.data_disk_backup
    replicate = var.data_disk_replicate
  }

  # -------------------------------------------------------------------------
  # SCSI Controller Configuration
  # -------------------------------------------------------------------------

  scsi_hardware = var.vm_scsi_hardware

  # -------------------------------------------------------------------------
  # Network Configuration
  # -------------------------------------------------------------------------

  network_device {
    bridge       = var.vm_network_bridge
    mac_address  = var.vm_network_mac_address
    model        = var.vm_network_model
    enabled      = var.vm_network_enabled
    firewall     = var.vm_network_firewall
    disconnected = var.vm_network_disconnected
    mtu          = var.vm_network_mtu
    rate_limit   = var.vm_network_rate_limit
  }

  # -------------------------------------------------------------------------
  # Operating System Configuration
  # -------------------------------------------------------------------------
  operating_system {
    type = var.vm_os_type
  }

  # ---------------------------------------------------------------------------
  # TPM 2.0 for Security Features
  # ---------------------------------------------------------------------------
  tpm_state {
    datastore_id = var.vm_disk_datastore
    version      = "v2.0"
  }

  # -------------------------------------------------------------------------
  # Cloud-Init Configuration (for new VM provisioning)
  # -------------------------------------------------------------------------
  # Configures cloud-init for automated user provisioning and system setup

  dynamic "initialization" {
    for_each = var.cloudinit_enabled && var.vm_create_new ? [1] : []

    content {
      datastore_id = var.vm_disk_datastore
      interface    = var.cloud_init_interface

      dns {
        servers = var.vm_dns_servers
      }

      ip_config {
        ipv4 {
          address = var.vm_use_dhcp ? "dhcp" : var.vm_ip_address
          gateway = var.vm_use_dhcp ? null : var.vm_gateway
        }
      }

      user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_config[count.index].id
    }
  }

  # -------------------------------------------------------------------------
  # USB Device Passthrough Configuration
  # -------------------------------------------------------------------------
  # Passes USB devices directly to the VM for native device access
  #
  # Finding Your USB Devices:
  # On Proxmox host, run:
  #   lsusb
  #
  # Example output:
  #   Bus 001 Device 003: ID 046d:c328 Logitech, Inc. Corded Mouse M500
  #   Bus 004 Device 002: ID 413c:2113 Dell Computer Corp. KB216 Keyboard
  #
  # USB ID Formats (two options):
  #
  # Format 1: Vendor:Product ID (recommended for stable identification)
  #   Example: "046d:c328" (Logitech Mouse)
  #   Use when: Device may be plugged into different USB ports
  #   Note: All devices with same vendor:product will be passed through
  #
  # Format 2: Hub Port (specific port assignment)
  #   Example: "1-4" or "4-2.3" (Bus 4, Port 2, Subport 3)
  #   Use when: Need specific physical port passthrough
  #   Note: Device must remain in the same USB port
  #
  # USB 3.0 vs USB 2.0:
  # - usb3=true: Use for storage devices, high-speed peripherals
  # - usb3=false: Use for keyboards, mice (better compatibility)
  #
  # Important Notes:
  # - Passed-through USB devices are NOT accessible to Proxmox host
  # - Hot-plug support depends on guest OS and device drivers
  # - USB hubs can be passed through to passthrough all connected devices
  # - Some USB devices (webcams, audio) may need additional configuration
  #
  # Troubleshooting USB Passthrough:
  # - Device not found: Verify device ID with lsusb
  # - Device not working: Try different USB port or format
  # - Performance issues: Enable usb3 for high-bandwidth devices
  # - Device resets: Check power management settings in guest OS
  #
  # Usage: Comment out unused USB blocks or set host to empty string ""

  # USB Device 1: Keyboard or primary input
  # usb {
  #   host = var.vm_usb_device_1_host # USB ID (e.g., "046d:c328" or "1-4")
  #   usb3 = var.vm_usb_device_1_usb3 # false for keyboards (better compatibility)
  # }

  # # USB Device 2: Mouse or secondary input
  # usb {
  #   host = var.vm_usb_device_2_host # USB ID (e.g., "413c:2113" or "4-2")
  #   usb3 = var.vm_usb_device_2_usb3 # false for mice (better compatibility)
  # }

  # # USB Device 3: Additional peripheral or hub
  # usb {
  #   host = var.vm_usb_device_3_host # USB ID (e.g., "0951:1666" or "4-2.3")
  #   usb3 = var.vm_usb_device_3_usb3 # true for storage devices
  # }

  # # USB Device 4: Storage or additional device
  # usb {
  #   host = var.vm_usb_device_4_host # USB ID or empty "" if not used
  #   usb3 = var.vm_usb_device_4_usb3 # true for high-speed devices
  # }

  # -------------------------------------------------------------------------
  # Timeout Configuration
  # -------------------------------------------------------------------------
  # Adjust timeouts for various VM operations

  timeout_create      = var.vm_timeout_create
  timeout_clone       = var.vm_timeout_clone
  timeout_start_vm    = var.vm_timeout_start_vm
  timeout_shutdown_vm = var.vm_timeout_shutdown_vm
  timeout_stop_vm     = var.vm_timeout_stop_vm
  timeout_reboot      = var.vm_timeout_reboot
  timeout_migrate     = var.vm_timeout_migrate
}

# -----------------------------------------------------------------------------
# Wait for VM to be Ready
# -----------------------------------------------------------------------------

resource "terraform_data" "wait_for_vm" {
  triggers_replace = {
    vm_id = proxmox_virtual_environment_vm.tumbleweed_vm[0].vm_id
  }

  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for VM to boot and SSH to become available..."
      VM_IP="${local.vm_ip}"
      
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

  depends_on = [proxmox_virtual_environment_vm.tumbleweed_vm]
}
