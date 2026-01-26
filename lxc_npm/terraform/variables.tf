# =============================================================================
# Nginx Proxy Manager LXC Container - Terraform Variables
# =============================================================================
#
# Last Updated: January 2026
# =============================================================================

# =============================================================================
# Vault Configuration Variables
# =============================================================================

variable "vault_address" {
  description = "HashiCorp Vault server address (e.g., https://vault.example.com:8200)"
  type        = string
}

variable "vault_username" {
  description = "Vault username for userpass authentication"
  type        = string
  default     = "admin"
}

variable "vault_password" {
  description = "Vault password for userpass authentication (recommended: set via TF_VAR_vault_password environment variable)"
  type        = string
  sensitive   = true
}

variable "vault_skip_tls_verify" {
  description = "Skip TLS certificate verification for Vault (only use in dev/lab environments)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Vault Data Sources Configuration
# -----------------------------------------------------------------------------

variable "proxmox_api_token_vault_path" {
  description = "Vault path to Proxmox API token secret"
  type        = string
}

variable "proxmox_endpoint_vault_path" {
  description = "Vault path to Proxmox endpoint URL secret"
  type        = string
}

variable "proxmox_node_name_vault_path" {
  description = "Vault path to Proxmox node name secret"
  type        = string
}

variable "proxmox_user_name_vault_path" {
  description = "Vault path to Proxmox user name secret"
  type        = string
}

variable "proxmox_root_name_vault_path" {
  description = "Vault path to Proxmox root name secret"
  type        = string
}

variable "proxmox_root_password_vault_path" {
  description = "Vault path to Proxmox root password secret"
  type        = string
}

variable "s3_bucket_name_vault_path" {
  description = "Vault path to S3 bucket name secret"
  type        = string
}

variable "ephemeral_vault_mount_path" {
  description = "Vault mount path for ephemeral secrets"
  type        = string
  default     = "secrets/"
}

# -----------------------------------------------------------------------------
# SSH Key Vault Paths
# -----------------------------------------------------------------------------

variable "root_ssh_public_key_path" {
  description = "Vault path to SSH public key for root access"
  type        = string
}

variable "root_ssh_private_key_path" {
  description = "Vault path to SSH private key for root access"
  type        = string
}

# -----------------------------------------------------------------------------
# AWS Configuration (for S3 Backend State Storage)
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for S3 backend state storage"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in format: xx-xxxx-N (e.g., us-east-1, eu-central-1)."
  }
}

# -----------------------------------------------------------------------------
# Proxmox Connection Variables
# -----------------------------------------------------------------------------

variable "connection_insecure" {
  description = "Skip TLS certificate verification (set false in production)"
  type        = bool
  default     = true
}

variable "ssh_agent_enabled" {
  description = "Use SSH agent for authentication"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# LXC Container Identity Variables
# -----------------------------------------------------------------------------

variable "lxc_id" {
  description = "Unique container ID (VMID) in Proxmox"
  type        = number
  default     = 105

  validation {
    condition     = var.lxc_id >= 100 && var.lxc_id <= 999999999
    error_message = "Container ID must be between 100 and 999999999."
  }
}

variable "lxc_hostname" {
  description = "Container hostname"
  type        = string
  default     = "npm"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.lxc_hostname))
    error_message = "Hostname must start with letter, contain only lowercase letters, numbers, hyphens, max 63 chars."
  }
}

variable "lxc_description" {
  description = "Container description shown in Proxmox GUI"
  type        = string
  default     = "Nginx Proxy Manager - Reverse Proxy Management - Managed by OpenTofu"
}

variable "lxc_tags" {
  description = "Tags for container organization in Proxmox"
  type        = list(string)
  default     = ["lxc", "npm", "proxy", "tofu-managed"]
}

# -----------------------------------------------------------------------------
# LXC Container Resource Variables
# -----------------------------------------------------------------------------

variable "lxc_cpu_cores" {
  description = "Number of CPU cores allocated to the container"
  type        = number
  default     = 2

  validation {
    condition     = var.lxc_cpu_cores >= 1 && var.lxc_cpu_cores <= 128
    error_message = "CPU cores must be between 1 and 128."
  }
}

variable "lxc_memory" {
  description = "Dedicated memory in MB (NPM requires ~2GB for build)"
  type        = number
  default     = 2048

  validation {
    condition     = var.lxc_memory >= 512
    error_message = "Minimum memory is 512 MB."
  }
}

variable "lxc_swap" {
  description = "Swap memory in MB (0 to disable)"
  type        = number
  default     = 512
}

variable "lxc_disk_size" {
  description = "Root filesystem size in GB"
  type        = number
  default     = 8

  validation {
    condition     = var.lxc_disk_size >= 4
    error_message = "Minimum disk size is 4 GB."
  }
}

variable "lxc_disk_storage" {
  description = "Storage pool for container rootfs (e.g., local-lvm, local-zfs)"
  type        = string
  default     = "local-lvm"
}

variable "lxc_startup_order" {
  description = "Startup order for container (lower numbers start first)"
  type        = number
  default     = 10
}

variable "lxc_up_delay" {
  description = "Delay in seconds before starting this container after the previous one"
  type        = number
  default     = 10
}

variable "lxc_down_delay" {
  description = "Delay in seconds before stopping this container before the next one"
  type        = number
  default     = 10
}

# -----------------------------------------------------------------------------
# LXC Bind Mount Configuration (Data Persistence)
# -----------------------------------------------------------------------------
# Bind mounts allow persistent storage that survives container recreation.
# NOTE: Bind mounts may require privileged containers (lxc_unprivileged = false)
# or proper ID mapping on the host if using unprivileged containers.

variable "lxc_npm_data_mount_volume" {
  description = "Host path for NPM data directory (SSL certs, database, configs)"
  type        = string
  default     = "/rpool/data/npm-data"
}

variable "lxc_npm_data_mount_path" {
  description = "Container path for NPM data directory"
  type        = string
  default     = "/data"
}

variable "lxc_npm_letsencrypt_mount_volume" {
  description = "Host path for Let's Encrypt data (SSL certificates)"
  type        = string
  default     = "/rpool/data/npm-letsencrypt"
}

variable "lxc_npm_letsencrypt_mount_path" {
  description = "Container path for Let's Encrypt data"
  type        = string
  default     = "/etc/letsencrypt"
}

# -----------------------------------------------------------------------------
# LXC Container Template Variables
# -----------------------------------------------------------------------------

variable "lxc_template_storage" {
  description = "Storage pool containing LXC templates"
  type        = string
  default     = "local"
}

variable "lxc_template_file" {
  description = "LXC template filename (must exist on Proxmox)"
  type        = string
  default     = "debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "lxc_os_type" {
  description = "Operating system type for the container"
  type        = string
  default     = "debian"
}

# -----------------------------------------------------------------------------
# LXC Container Network Variables
# -----------------------------------------------------------------------------

variable "lxc_network_bridge" {
  description = "Network bridge to attach container to"
  type        = string
  default     = "vmbr0"
}

variable "lxc_network_interface_name" {
  description = "Name of the network interface inside the container"
  type        = string
  default     = "eth0"
}

variable "lxc_ip_address" {
  description = "IPv4 address with CIDR (e.g., 192.168.1.105/24) or 'dhcp'"
  type        = string
  default     = "dhcp"
}

variable "lxc_gateway" {
  description = "Default gateway IP (required if using static IP)"
  type        = string
  default     = ""
}

variable "lxc_dns_servers" {
  description = "DNS servers (space-separated)"
  type        = string
  default     = "8.8.8.8 8.8.4.4"
}

# -----------------------------------------------------------------------------
# LXC Container Security Variables
# -----------------------------------------------------------------------------

variable "lxc_unprivileged" {
  description = "Run as unprivileged container (recommended for security)"
  type        = bool
  default     = true
}

variable "lxc_start_on_boot" {
  description = "Start container automatically on Proxmox boot"
  type        = bool
  default     = true
}

variable "lxc_protection" {
  description = "Protect container from accidental deletion"
  type        = bool
  default     = false
}

variable "lxc_nesting" {
  description = "Enable nesting (required for systemd in container)"
  type        = bool
  default     = true
}

variable "lxc_started" {
  description = "Ensure container is started after creation"
  type        = bool
  default     = true
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
# NPM Port Configuration
# -----------------------------------------------------------------------------

variable "npm_http_port" {
  description = "HTTP proxy port"
  type        = number
  default     = 80

  validation {
    condition     = var.npm_http_port >= 1 && var.npm_http_port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "npm_https_port" {
  description = "HTTPS proxy port"
  type        = number
  default     = 443

  validation {
    condition     = var.npm_https_port >= 1 && var.npm_https_port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "npm_admin_port" {
  description = "NPM Admin UI port"
  type        = number
  default     = 81

  validation {
    condition     = var.npm_admin_port >= 1 && var.npm_admin_port <= 65535
    error_message = "Port must be between 1 and 65535."
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
# NetBox Configuration
# -----------------------------------------------------------------------------

variable "netbox_url" {
  description = "NetBox server URL"
  type        = string
}

variable "netbox_insecure" {
  description = "Skip TLS verification for NetBox server (use for self-signed certs)"
  type        = bool
  default     = true
}

variable "netbox_api_token_vault_path" {
  description = "Vault path to NetBox API token secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "site_name" {
  description = "NetBox site name for the container"
  type        = string
  default     = "site_01"
}

variable "cluster_name" {
  description = "NetBox cluster name for the container"
  type        = string
  default     = "cluster_01"
}

variable "device_id" {
  description = "NetBox device ID for the container"
  type        = number
  default     = 1
}

variable "vrf_name" {
  description = "NetBox VRF name for the container"
  type        = string
  default     = "vrf_01"
}

variable "tenant_name" {
  description = "NetBox tenant name for the container"
  type        = string
  default     = "tenant_01"
}

variable "interface_name" {
  description = "Name of the interface"
  type        = string
  default     = "eth0"
}

variable "disk_name" {
  description = "Name of the disk"
  type        = string
  default     = "disk-01"
}

variable "disk_description" {
  description = "Description of the disk"
  type        = string
  default     = "Main disk"
}

variable "service_user_uid" {
  description = "UID of the service user inside the container (for permission fix script)"
  type        = number
  default     = 0 # Default to root for NPM as it runs as root
}

variable "service_user_gid" {
  description = "GID of the service user inside the container (for permission fix script)"
  type        = number
  default     = 0 # Default to root for NPM as it runs as root
}
