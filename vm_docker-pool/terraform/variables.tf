# =============================================================================
# VM Docker Pool - Variables Definition
# =============================================================================
#
# This file defines all input variables for the Docker Pool VM module.
# Variables are organized into logical groups for better maintainability.
#
# Security Best Practices:
# - Sensitive variables are marked with `sensitive = true`
# - Never commit actual values to version control
# - Use terraform.tfvars (gitignored) or Vault for secrets
#
# Last Updated: January 2026
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

variable "vault_username" {
  description = "Vault username for userpass authentication"
  type        = string
  default     = "admin"
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

variable "proxmox_user_name_vault_path" {
  description = "Vault path for Proxmox SSH user (ansible)"
  type        = string
  default     = "secret/proxmox/user"
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
  default     = "us-east-1"
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

variable "vm_id" {
  description = "Unique VM ID in Proxmox (100-999999999)"
  type        = number
  default     = 300

  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999999
    error_message = "VM ID must be between 100 and 999999999."
  }
}

variable "vm_hostname" {
  description = "Hostname for the virtual machine"
  type        = string
  default     = "docker-pool"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.vm_hostname))
    error_message = "Hostname must be valid (alphanumeric and hyphens, 1-63 chars)."
  }
}

variable "vm_description" {
  description = "Description of the virtual machine"
  type        = string
  default     = "Ubuntu Server 24.04.3 LTS with Docker and Portainer - managed by OpenTofu"
}

variable "vm_tags" {
  description = "Tags for VM organization and filtering"
  type        = list(string)
  default     = ["tofu-managed", "docker", "portainer", "ubuntu"]
}

# -----------------------------------------------------------------------------
# VM Resource Variables
# -----------------------------------------------------------------------------

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

variable "vm_memory" {
  description = "Dedicated memory in MB (4096 = 4GB recommended for Docker)"
  type        = number
  default     = 4096

  validation {
    condition     = var.vm_memory >= 512
    error_message = "Minimum memory is 512 MB."
  }
}

variable "vm_memory_floating" {
  description = "Floating (balloon) memory in MB (0 = disabled)"
  type        = number
  default     = 0
}

variable "vm_disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 32

  validation {
    condition     = var.vm_disk_size >= 10
    error_message = "Boot disk must be at least 10 GB for Docker workloads."
  }
}

variable "vm_disk_datastore" {
  description = "Storage pool for VM disk"
  type        = string
  default     = "local-lvm"
}

variable "vm_disk_interface" {
  description = "Disk interface (scsi0, virtio0, etc.)"
  type        = string
  default     = "scsi0"
}

variable "vm_machine_type" {
  description = "Machine type (q35 recommended for modern guests)"
  type        = string
  default     = "q35"
}

# -----------------------------------------------------------------------------
# VM Network Variables
# -----------------------------------------------------------------------------

variable "vm_ip_address" {
  description = "IPv4 address with CIDR (e.g., 198.51.100.200/24)"
  type        = string
  default     = "198.51.100.200/24"

  validation {
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$", var.vm_ip_address))
    error_message = "IP address must be in CIDR format (e.g., 198.51.100.200/24)."
  }
}

variable "vm_gateway" {
  description = "Default gateway IP address"
  type        = string
  default     = "198.51.100.1"
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

# -----------------------------------------------------------------------------
# VM Lifecycle Variables
# -----------------------------------------------------------------------------

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

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,31}$", var.ansible_user_name))
    error_message = "Ansible username must start with letter, contain only lowercase letters, numbers, hyphens, underscores, max 32 chars."
  }
}

variable "ansible_ssh_public_key_path" {
  description = "Path to SSH public key file for Ansible user (separate from root key recommended)"
  type        = string
  default     = "~/.ssh/ansible_rsa.pub"
}

variable "ansible_user_sudo" {
  description = "Grant Ansible user passwordless sudo access (NOPASSWD:ALL)"
  type        = bool
  default     = true
}

variable "ansible_user_sudo_commands" {
  description = "Specific sudo commands allowed for Ansible user (empty list = ALL commands if sudo enabled)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cmd in var.ansible_user_sudo_commands : can(regex("^/", cmd))
    ])
    error_message = "Sudo commands must be absolute paths (start with /)."
  }
}

variable "ansible_user_groups" {
  description = "Additional groups for Ansible user (sudo group added automatically if ansible_user_sudo=true)"
  type        = list(string)
  default     = []
}

variable "ansible_user_shell" {
  description = "Shell for Ansible user"
  type        = string
  default     = "/bin/bash"

  validation {
    condition     = contains(["/bin/bash", "/bin/sh", "/bin/zsh", "/bin/dash"], var.ansible_user_shell)
    error_message = "Shell must be one of: /bin/bash, /bin/sh, /bin/zsh, /bin/dash."
  }
}

# -----------------------------------------------------------------------------
# Password Generation Variables
# -----------------------------------------------------------------------------

variable "password_length" {
  description = "Length of generated passwords"
  type        = number
  default     = 25

  validation {
    condition     = var.password_length >= 16
    error_message = "Password must be at least 16 characters for security."
  }
}

variable "password_special_chars" {
  description = "Special characters allowed in generated passwords"
  type        = string
  default     = "!@#$%^&*"
}

variable "password_lower_chars_count" {
  description = "Minimum number of lowercase characters in generated passwords"
  type        = number
  default     = 4
}

variable "password_upper_chars_count" {
  description = "Minimum number of uppercase characters in generated passwords"
  type        = number
  default     = 4
}

variable "password_numeric_count" {
  description = "Minimum number of numeric characters in generated passwords"
  type        = number
  default     = 4
}

variable "password_special_chars_count" {
  description = "Minimum number of special characters in generated passwords"
  type        = number
  default     = 4
}

variable "vm_username" {
  description = "Default vm username"
  type        = string
  default     = "root"
}

# -----------------------------------------------------------------------------
# Cloud Image Variables
# -----------------------------------------------------------------------------

variable "vm_cloud_image_url" {
  description = "URL to download Ubuntu cloud image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"

  validation {
    condition     = can(regex("^https://", var.vm_cloud_image_url))
    error_message = "Cloud image URL must use HTTPS for security."
  }
}

variable "vm_cloud_image_filename" {
  description = "Filename for the downloaded cloud image"
  type        = string
  default     = "ubuntu-24.04-server-cloudimg-amd64.qcow2"
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
# Portainer Bind Mount Variables
# -----------------------------------------------------------------------------

variable "portainer_bind_mount_enabled" {
  description = "Enable bind mount for Portainer data persistence"
  type        = bool
  default     = true
}

variable "portainer_bind_mount_source" {
  description = "Source path on Proxmox host for Portainer data"
  type        = string
  default     = "/rpool/datastore/portainer"

  validation {
    condition     = can(regex("^/rpool/", var.portainer_bind_mount_source))
    error_message = "Bind mount must be under /rpool/ for safety."
  }
}

variable "portainer_bind_mount_target" {
  description = "Target path inside VM for Portainer data"
  type        = string
  default     = "/opt/portainer/data"
}

# -----------------------------------------------------------------------------
# NetBox Registration Variables
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "NetBox cluster name for VM registration"
  type        = string
  default     = "Proxmox Cluster"
}

variable "site_name" {
  description = "NetBox site name"
  type        = string
  default     = "Home Lab"
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
  default     = "Boot disk for Docker Pool VM"
}
