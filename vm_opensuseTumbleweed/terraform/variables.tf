# =============================================================================
# VM OpenSUSE Tumbleweed - Variables Definition
# =============================================================================

# -----------------------------------------------------------------------------
# Vault Configuration Variables
# -----------------------------------------------------------------------------

variable "vault_address" {
  description = "HashiCorp Vault server address"
  type        = string
  default     = "https://127.0.0.1:8200"
}

variable "vault_skip_tls_verify" {
  description = "Skip TLS certificate verification for Vault (dev only)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Encryption Configuration Variables
# -----------------------------------------------------------------------------
variable "transit_engine_path" {
  description = "Vault Transit secrets engine mount path"
  type        = string
  default     = "transit"
}

variable "transit_key_name" {
  description = "Name of the encryption key in Vault Transit engine"
  type        = string
}

variable "transit_key_length" {
  description = "Length of the encryption key in bytes (e.g., 32 for 256-bit AES)"
  type        = number
  default     = 32
}

# -----------------------------------------------------------------------------
# Vault Secret Paths
# -----------------------------------------------------------------------------

variable "proxmox_endpoint_vault_path" {
  description = "Vault path for Proxmox API endpoint URL"
  type        = string
  default     = "secret/proxmox/endpoint"
}

variable "proxmox_node_name_vault_path" {
  description = "Vault path for Proxmox node name"
  type        = string
  default     = "secret/proxmox/node"
}

variable "proxmox_root_name_vault_path" {
  description = "Vault path for Proxmox root user"
  type        = string
  default     = "secret/proxmox/root"
}

variable "proxmox_root_password_vault_path" {
  description = "Vault path for Proxmox root password (ephemeral)"
  type        = string
  default     = "proxmox/root"
}

variable "proxmox_api_token_vault_path" {
  description = "Vault path for Proxmox API token (ephemeral)"
  type        = string
  default     = "proxmox/api_token"
}

variable "root_ssh_public_key_path" {
  description = "Vault path for root SSH public key"
  type        = string
  default     = "secret/ssh/root"
}

variable "root_ssh_private_key_path" {
  description = "Vault path for root SSH private key (ephemeral)"
  type        = string
  default     = "ssh/root"
}

variable "ansible_ssh_public_key_path" {
  description = "Vault path for Ansible SSH public key"
  type        = string
  default     = "secret/ssh/ansible"
}

variable "s3_bucket_name_vault_path" {
  description = "Vault path for S3 bucket name"
  type        = string
  default     = "secret/aws/s3"
}

variable "ephemeral_vault_mount_path" {
  description = "Vault KV v2 mount path for ephemeral secrets"
  type        = string
  default     = "secret"
}

# -----------------------------------------------------------------------------
# NetBox Configuration Variables
# -----------------------------------------------------------------------------

variable "netbox_url" {
  description = "NetBox server URL"
  type        = string
  default     = "https://127.0.0.1:8000"
}

variable "netbox_insecure" {
  description = "Skip TLS verification for NetBox (self-signed certs)"
  type        = bool
  default     = true
}

variable "netbox_api_token_vault_path" {
  description = "Vault path for NetBox API token (ephemeral)"
  type        = string
  default     = "netbox/api_token"
}

# -----------------------------------------------------------------------------
# AWS Configuration Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for S3 backend"
  type        = string
  default     = "eu-central-1"
}

# -----------------------------------------------------------------------------
# Proxmox Connection Variables
# -----------------------------------------------------------------------------

variable "connection_insecure" {
  description = "Skip TLS certificate verification for Proxmox API"
  type        = bool
  default     = true
}

variable "ssh_agent_enabled" {
  description = "Use SSH agent for Proxmox host authentication"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# VM Identity Variables
# -----------------------------------------------------------------------------

variable "vm_create_new" {
  description = "Create a new VM (true) or manage existing VM (false). Set to true for new deployments, false for existing VMs"
  type        = bool
  default     = false
}

variable "cloud_init_interface" {
  description = "Interface for cloud-init (ide2, scsi1, etc.)"
  type        = string
  default     = "ide2"
}

variable "cloud_image_download" {
  description = "Download cloud image (true) or use existing disk image (false)"
  type        = bool
  default     = true
}

variable "vm_id" {
  description = "Unique VM ID in Proxmox (100-999999999)"
  type        = number
  default     = 400 # Default distinct from docker-pool (300)

  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999999
    error_message = "VM ID must be between 100 and 999999999."
  }
}

variable "vm_hostname" {
  description = "Hostname for the virtual machine"
  type        = string
  default     = "opensuseTumbleweed-vm"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.vm_hostname))
    error_message = "Hostname must be valid (alphanumeric and hyphens, 1-63 chars)."
  }
}

variable "vm_description" {
  description = "Description of the virtual machine"
  type        = string
  default     = "OpenSUSE Tumbleweed VM - Managed by OpenTofu"
}

variable "vm_tags" {
  description = "Tags for VM organization and filtering"
  type        = list(string)
  default     = ["tofu-managed", "opensuse", "Tumbleweed"]
}

# -----------------------------------------------------------------------------
# VM Resource Variables
# -----------------------------------------------------------------------------

variable "vm_bios" {
  description = "BIOS type (ovmf for UEFI, seabios for BIOS)"
  type        = string
  default     = "ovmf"
}

variable "vm_machine_type" {
  description = "Machine type (q35 recommended for modern guests)"
  type        = string
  default     = "q35"
}

variable "vm_cpu_architecture" {
  description = "CPU architecture (x86_64 or aarch64 )"
  type        = string
  default     = "x86_64"
}

variable "vm_cpu_sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}

variable "vm_cpu_hotplugged" {
  description = "Enable hot-plugging of CPU cores"
  type        = number
  default     = 0
}

variable "vm_cpu_limit" {
  description = "CPU core limit (0 = no limit)"
  type        = number
  default     = 0
}

variable "vm_cpu_units" {
  description = "CPU scheduling units (higher = more priority)"
  type        = number
  default     = 1024
}

variable "vm_cpu_numa" {
  description = "Enable NUMA support"
  type        = bool
  default     = false
}

variable "vm_cpu_cores" {
  description = "Number of CPU cores allocated to the VM"
  type        = number
  default     = 2

  validation {
    condition     = var.vm_cpu_cores >= 1 && var.vm_cpu_cores <= 128
    error_message = "CPU cores must be between 1 and 128."
  }
}

variable "vm_cpu_type" {
  description = "CPU type (host = best performance, x86-64-v2-AES = portable)"
  type        = string
  default     = "x86-64-v2-AES"
}

variable "vm_boot_order" {
  description = "Boot order for the VM"
  type        = list(string)
  default     = ["scsi0", "ide2", "net0"]
}

variable "vm_efi_disk_file_format" {
  description = "File format for EFI disk (raw recommended for performance)"
  type        = string
  default     = "raw"
}

variable "vm_efi_disk_type" {
  description = "Type for EFI disk (4m recommended for UEFI)"
  type        = string
  default     = "4m"
}

variable "vm_os_type" {
  description = "Operating system type (l26 for OpenSUSE Tumbleweed)"
  type        = string
  default     = "l26"
}

variable "vm_memory_dedicated" {
  description = "Dedicated memory in MB"
  type        = number
  default     = 4096

  validation {
    condition     = var.vm_memory_dedicated >= 1024
    error_message = "Minimum memory is 1024 MB."
  }
}

variable "vm_memory_floating" {
  description = "Floating (balloon) memory in MB (0 = disabled)"
  type        = number
  default     = 0
}

variable "vm_memory_keep_hugepages" {
  description = "Keep hugepages (true = enabled, false = disabled)"
  type        = bool
  default     = false
}

variable "vm_boot_disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 32
}

variable "vm_disk_datastore" {
  description = "Storage pool for VM disks (boot and data)"
  type        = string
  default     = "local-lvm"
}

variable "vm_disk_interface" {
  description = "Disk interface (scsi0, virtio0, etc.)"
  type        = string
  default     = "scsi0"
}

variable "vm_disk_discard" {
  description = "Enable discard (TRIM) for the boot disk"
  type        = string
  default     = "on"
}

variable "vm_disk_ssd" {
  description = "Enable SSD mode for the boot disk"
  type        = bool
  default     = true
}

variable "vm_disk_aio" {
  description = "Enable AIO for the boot disk"
  type        = string
  default     = "io_uring"
}

variable "vm_disk_cache" {
  description = "Enable cache for the boot disk"
  type        = string
  default     = "writeback"
}

variable "vm_disk_iothread" {
  description = "Enable I/O thread for the boot disk"
  type        = bool
  default     = true
}

variable "vm_disk_backup" {
  description = "Enable backup for the boot disk"
  type        = bool
  default     = true
}

variable "vm_disk_replicate" {
  description = "Enable replication for the boot disk"
  type        = bool
  default     = true
}

variable "vm_scsi_hardware" {
  description = "SCSI controller hardware type"
  type        = string
  default     = "virtio-scsi-single"
}

# -----------------------------------------------------------------------------
# Secondary Data Disk (Persistence)
# -----------------------------------------------------------------------------

variable "data_disk_size" {
  description = "Size of secondary data disk in GB (for /home or /data)"
  type        = number
  default     = 50
}

variable "data_disk_datastore" {
  description = "Datastore for secondary data disk"
  type        = string
  default     = "local-lvm"
}

variable "data_disk_file_format" {
  description = "File format for data disk (raw recommended for performance)"
  type        = string
  default     = "raw"
}

variable "data_disk_interface" {
  description = "Disk interface for data disk (scsi0, virtio0, etc.)"
  type        = string
  default     = "scsi1"
}

variable "data_disk_discard" {
  description = "Enable discard (TRIM) for the data disk"
  type        = string
  default     = "ignore"
}

variable "data_disk_ssd" {
  description = "Enable SSD mode for the data disk"
  type        = bool
  default     = true
}

variable "data_disk_iothread" {
  description = "Enable I/O thread for the data disk"
  type        = bool
  default     = true
}

variable "data_disk_backup" {
  description = "Enable backup for the data disk"
  type        = bool
  default     = true
}

variable "data_disk_replicate" {
  description = "Enable replication for the data disk"
  type        = bool
  default     = true
}

variable "data_disk_aio" {
  description = "Enable AIO for the data disk"
  type        = string
  default     = "io_uring"
}

variable "data_disk_cache" {
  description = "Enable cache for the data disk"
  type        = string
  default     = "writeback"
}

# -----------------------------------------------------------------------------
# VM Network Variables
# -----------------------------------------------------------------------------

variable "vm_use_dhcp" {
  description = "Use DHCP for network interface"
  type        = bool
  default     = false
}

variable "vm_ip_address" {
  description = "IPv4 address with CIDR (e.g., 192.168.0.210/24)"
  type        = string
  default     = "192.168.0.210/24"

  validation {
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$", var.vm_ip_address))
    error_message = "IP address must be in CIDR format."
  }
}

variable "vm_gateway" {
  description = "Default gateway IP address"
  type        = string
  default     = "192.168.0.1"
}

variable "vm_dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "vm_network_bridge" {
  description = "Network bridge to attach VM to"
  type        = string
  default     = "vmbr0"
}

variable "vm_network_model" {
  description = "Network interface model (virtio is standard for Linux)"
  type        = string
  default     = "virtio"
}

variable "vm_network_mac_address" {
  description = "MAC address for the network interface"
  type        = string
  default     = ""
}

variable "vm_network_enabled" {
  description = "Enable the network interface"
  type        = bool
  default     = true
}

variable "vm_network_firewall" {
  description = "Enable firewall for the network interface"
  type        = bool
  default     = false
}

variable "vm_network_disconnected" {
  description = "Disconnect the network interface"
  type        = bool
  default     = false
}

variable "vm_network_mtu" {
  description = "MTU for the network interface"
  type        = number
  default     = 1
}

variable "vm_network_rate_limit" {
  description = "Rate limit for the network interface"
  type        = number
  default     = 0
}

# -----------------------------------------------------------------------------
# USB Device Passthrough Configuration
# -----------------------------------------------------------------------------

variable "vm_usb_device_1_host" {
  description = "USB device 1 host identifier (vendor:product or bus-port)"
  type        = string
  default     = "212e:1534"
}

variable "vm_usb_device_1_usb3" {
  description = "Enable USB 3.0 for device 1"
  type        = bool
  default     = false
}

variable "vm_usb_device_2_host" {
  description = "USB device 2 host identifier (vendor:product or bus-port)"
  type        = string
  default     = "1-4"
}

variable "vm_usb_device_2_usb3" {
  description = "Enable USB 3.0 for device 2"
  type        = bool
  default     = false
}

variable "vm_usb_device_3_host" {
  description = "USB device 3 host identifier (vendor:product or bus-port)"
  type        = string
  default     = "4-2.4"
}

variable "vm_usb_device_3_usb3" {
  description = "Enable USB 3.0 for device 3"
  type        = bool
  default     = false
}

variable "vm_usb_device_4_host" {
  description = "USB device 4 host identifier (vendor:product or bus-port)"
  type        = string
  default     = "046d:c328"
}

variable "vm_usb_device_4_usb3" {
  description = "Enable USB 3.0 for device 4"
  type        = bool
  default     = false
}


# -----------------------------------------------------------------------------
# VM Lifecycle Variables
# -----------------------------------------------------------------------------

variable "vm_on_boot" {
  description = "Start the VM on boot"
  type        = bool
  default     = true
}

variable "vm_started" {
  description = "Start the VM immediately after creation"
  type        = bool
  default     = true
}

variable "vm_stop_on_destroy" {
  description = "Stop the VM when the resource is destroyed"
  type        = bool
  default     = true
}

variable "vm_template" {
  description = "Convert the VM to a template"
  type        = bool
  default     = false
}

variable "vm_migrate" {
  description = "Migrate the VM when the resource is updated"
  type        = bool
  default     = false
}

variable "vm_reboot" {
  description = "Reboot the VM when the resource is updated"
  type        = bool
  default     = false
}

variable "vm_protection" {
  description = "Protect the VM from accidental deletion"
  type        = bool
  default     = false
}

variable "vm_reboot_after_update" {
  description = "Reboot the VM after update"
  type        = bool
  default     = true
}

variable "vm_qemu_agent_enabled" {
  description = "Enable QEMU agent for VM management"
  type        = bool
  default     = true
}

variable "vm_qemu_agent_timeout" {
  description = "Timeout for QEMU agent operations"
  type        = string
  default     = "2m"
}

variable "vm_qemu_agent_trim" {
  description = "Enable QEMU agent trim"
  type        = bool
  default     = true
}

variable "vm_qemu_agent_type" {
  description = "QEMU agent type"
  type        = string
  default     = "virtio"
}

variable "vm_startup_order" {
  description = "Boot order priority (lower = earlier)"
  type        = string
  default     = "3"
}

variable "vm_startup_up_delay" {
  description = "Seconds to wait after starting this VM before starting the next"
  type        = string
  default     = "60"
}

variable "vm_startup_down_delay" {
  description = "Seconds to wait after stopping this VM before stopping the next"
  type        = string
  default     = "60"
}

# -----------------------------------------------------------------------------
# Timeout Configuration
# -----------------------------------------------------------------------------

variable "vm_timeout_create" {
  description = "Timeout for VM creation in seconds"
  type        = number
  default     = 1800
}

variable "vm_timeout_clone" {
  description = "Timeout for VM cloning in seconds"
  type        = number
  default     = 1800
}

variable "vm_timeout_start_vm" {
  description = "Timeout for starting VM in seconds"
  type        = number
  default     = 1800
}

variable "vm_timeout_shutdown_vm" {
  description = "Timeout for graceful VM shutdown in seconds"
  type        = number
  default     = 1800
}

variable "vm_timeout_stop_vm" {
  description = "Timeout for forceful VM stop in seconds"
  type        = number
  default     = 300
}

variable "vm_timeout_reboot" {
  description = "Timeout for VM reboot in seconds"
  type        = number
  default     = 1800
}

variable "vm_timeout_move_disk" {
  description = "Timeout for moving disk between datastores in seconds"
  type        = number
  default     = 1800
}

variable "vm_timeout_migrate" {
  description = "Timeout for VM migration in seconds"
  type        = number
  default     = 1800
}

# -----------------------------------------------------------------------------
# Ansible User Configuration Variables
# -----------------------------------------------------------------------------

variable "ansible_user_enabled" {
  description = "Enable creation of dedicated Ansible user for automation"
  type        = bool
  default     = true
}

variable "ansible_user_name" {
  description = "Username for Ansible automation user"
  type        = string
  default     = "ansible"
}

variable "ansible_user_sudo" {
  description = "Grant Ansible user passwordless sudo access (NOPASSWD:ALL)"
  type        = bool
  default     = true
}

variable "ansible_user_sudo_commands" {
  description = "Specific sudo commands allowed for Ansible user"
  type        = list(string)
  default     = []
}

variable "ansible_user_groups" {
  description = "Additional groups for Ansible user"
  type        = list(string)
  default     = []
}

variable "ansible_user_shell" {
  description = "Shell for Ansible user"
  type        = string
  default     = "/bin/bash"
}

# -----------------------------------------------------------------------------
# Password Generation Variables
# -----------------------------------------------------------------------------

variable "password_length" {
  description = "Length of generated passwords"
  type        = number
  default     = 25
}

variable "password_use_special_chars" {
  description = "Use special characters in generated passwords"
  type        = bool
  default     = true
}

variable "password_special_chars" {
  description = "Special characters allowed in generated passwords"
  type        = string
  default     = "!@#$%^&*"
}

variable "password_lower_chars_count" {
  description = "Minimum number of lowercase characters"
  type        = number
  default     = 4
}

variable "password_upper_chars_count" {
  description = "Minimum number of uppercase characters"
  type        = number
  default     = 4
}

variable "password_numeric_count" {
  description = "Minimum number of numeric characters"
  type        = number
  default     = 4
}

variable "password_special_chars_count" {
  description = "Minimum number of special characters"
  type        = number
  default     = 4
}

variable "vm_username" {
  description = "Default vm username (root)"
  type        = string
  default     = "root"
}

# -----------------------------------------------------------------------------
# Cloud Image Variables
# -----------------------------------------------------------------------------

variable "cloudinit_enabled" {
  description = "Enable cloud-init provisioning with user configuration (requires download_iso=true for new VMs)"
  type        = bool
  default     = true
}


variable "overwrite_cloud_image" {
  description = "Overwrite existing cloud image (true) or skip (false)"
  type        = bool
  default     = false
}

variable "cloud_image_checksum_verification" {
  description = "Enable cloud image checksum verification (true) or disable (false)"
  type        = bool
  default     = true
}

variable "cloud_image_upload_timeout" {
  description = "Timeout for cloud image upload (in seconds)"
  type        = number
  default     = 1800 # 30 minutes (sufficient for slow connections)
}

variable "cloud_image_checksum_algorithm" {
  description = "Checksum algorithm for cloud image verification"
  type        = string
  default     = "sha256"
}

variable "cloud_image_checksum" {
  description = "SHA256 checksum for cloud image verification"
  type        = string
  default     = ""
}

variable "vm_cloud_image_url" {
  description = "URL to download OpenSUSE cloud image"
  type        = string
  default     = "https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-1.0.0-Cloud-Snapshot20260131.qcow2"
}

variable "vm_cloud_image_filename" {
  description = "Filename for the downloaded cloud image"
  type        = string
  default     = "openSUSE-Tumbleweed-Minimal-VM.x86_64-1.0.0-Cloud-Snapshot20260131.qcow2"
}

variable "cloudinit_content_type" {
  description = "Content type for cloud-init data file"
  type        = string
  default     = "snippets"
}

variable "cloudinit_data_file_name" {
  description = "Filename for the cloud-init data file"
  type        = string
  default     = "user-data.yaml.tftpl"
}

variable "vm_cloud_image_datastore" {
  description = "Datastore for cloud image storage"
  type        = string
  default     = "local"
}

variable "image_download_content_type" {
  description = "Content type for downloaded files (import for cloud images)"
  type        = string
  default     = "import"
}

# -----------------------------------------------------------------------------
# NetBox Registration Variables
# -----------------------------------------------------------------------------

variable "vm_status_in_netbox" {
  description = "Status of the VM in NetBox"
  type        = string
  default     = "active"
}

variable "vm_ip_status_in_netbox" {
  description = "Status of the VM IP in NetBox"
  type        = string
  default     = "active"
}

variable "vm_netbox_object_type" {
  description = "NetBox object type for VM registration"
  type        = string
  default     = "virtualization.vminterface"
}

variable "cluster_name" {
  description = "NetBox cluster name for VM registration"
  type        = string
  default     = "Proxmox Cluster"
}

variable "site_name" {
  description = "NetBox site name"
  type        = string
  default     = "HomeLab"
}

variable "tenant_name" {
  description = "NetBox tenant name"
  type        = string
  default     = "Infrastructure"
}

variable "vrf_name" {
  description = "NetBox VRF name for IP addressing"
  type        = string
  default     = "Default"
}

variable "device_id" {
  description = "NetBox device ID for the Proxmox host"
  type        = number
  default     = 1
}

variable "interface_name" {
  description = "NetBox interface name for the VM"
  type        = string
  default     = "eth0"
}

variable "disk_name" {
  description = "NetBox virtual disk name"
  type        = string
  default     = "boot-disk"
}

variable "disk_description" {
  description = "NetBox virtual disk description"
  type        = string
  default     = "Boot disk for OpenSUSE VM"
}

variable "data_disk_name" {
  description = "NetBox virtual disk name"
  type        = string
  default     = "data-disk"
}

variable "data_disk_description" {
  description = "NetBox virtual disk description"
  type        = string
  default     = "Secondary Persistent Data Disk"
}