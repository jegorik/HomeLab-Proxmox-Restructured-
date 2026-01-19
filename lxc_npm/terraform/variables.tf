# =============================================================================
# Nginx Proxy Manager LXC Container - Terraform Variables
# =============================================================================
#
# Last Updated: January 2026
# =============================================================================

# -----------------------------------------------------------------------------
# Vault Configuration
# -----------------------------------------------------------------------------

variable "vault_address" {
  description = "HashiCorp Vault server address"
  type        = string
  sensitive   = true
}

variable "vault_token" {
  description = "Vault authentication token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_pve_secret_path" {
  description = "Vault path for Proxmox credentials"
  type        = string
  default     = "secrets/proxmox/root"
}

variable "vault_netbox_secret_path" {
  description = "Vault path for NetBox API token"
  type        = string
  default     = "secrets/proxmox/netbox_api_token"
}

# -----------------------------------------------------------------------------
# Proxmox Configuration
# -----------------------------------------------------------------------------

variable "pve_api_url" {
  description = "Proxmox API URL (e.g., https://192.168.1.100:8006/api2/json)"
  type        = string
}

variable "pve_target_node" {
  description = "Proxmox node to deploy LXC container"
  type        = string
  default     = "pve"
}

variable "pve_root_password" {
  description = "Proxmox root password (fallback if not using Vault)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# NetBox Configuration
# -----------------------------------------------------------------------------

variable "netbox_url" {
  description = "NetBox server URL"
  type        = string
}

variable "netbox_api_token" {
  description = "NetBox API token (fallback if not using Vault)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "netbox_site_id" {
  description = "NetBox site ID for the container"
  type        = number
  default     = 1
}

variable "netbox_cluster_id" {
  description = "NetBox cluster ID for the container"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Container Configuration
# -----------------------------------------------------------------------------

variable "container_id" {
  description = "LXC container VMID"
  type        = number
}

variable "container_hostname" {
  description = "Container hostname"
  type        = string
  default     = "npm"
}

variable "container_description" {
  description = "Container description"
  type        = string
  default     = "Nginx Proxy Manager - Reverse Proxy Management"
}

variable "container_template" {
  description = "LXC template (e.g., local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst)"
  type        = string
}

variable "container_onboot" {
  description = "Start container on boot"
  type        = bool
  default     = true
}

variable "container_start" {
  description = "Start container after creation"
  type        = bool
  default     = true
}

variable "container_unprivileged" {
  description = "Create unprivileged container"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Hardware Resources (NPM recommended: 2GB RAM, 2 cores)
# -----------------------------------------------------------------------------

variable "container_memory" {
  description = "Memory in MB (NPM requires ~2GB for build)"
  type        = number
  default     = 2048
}

variable "container_swap" {
  description = "Swap in MB"
  type        = number
  default     = 512
}

variable "container_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "container_disk_size" {
  description = "Root disk size in MB"
  type        = number
  default     = 8192
}

variable "container_storage" {
  description = "Proxmox storage for root disk"
  type        = string
  default     = "local-lvm"
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "network_ip" {
  description = "Container IP address (CIDR notation, e.g., 192.168.1.110/24)"
  type        = string
}

variable "network_gateway" {
  description = "Network gateway"
  type        = string
}

variable "network_dns" {
  description = "DNS server"
  type        = string
  default     = "8.8.8.8"
}

# -----------------------------------------------------------------------------
# SSH Configuration
# -----------------------------------------------------------------------------

variable "ssh_public_key" {
  description = "SSH public key for ansible user"
  type        = string
}

variable "ssh_user" {
  description = "SSH user for Ansible"
  type        = string
  default     = "ansible"
}

# -----------------------------------------------------------------------------
# NPM Ports
# -----------------------------------------------------------------------------

variable "npm_http_port" {
  description = "HTTP proxy port"
  type        = number
  default     = 80
}

variable "npm_https_port" {
  description = "HTTPS proxy port"
  type        = number
  default     = 443
}

variable "npm_admin_port" {
  description = "NPM Admin UI port"
  type        = number
  default     = 81
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags for the container"
  type        = list(string)
  default     = ["lxc", "npm", "proxy"]
}
