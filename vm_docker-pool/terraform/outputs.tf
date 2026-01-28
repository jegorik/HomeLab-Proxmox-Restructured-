# =============================================================================
# VM Docker Pool - Outputs
# =============================================================================
#
# Output values for the provisioned Docker Pool VM.
# These outputs are used by deploy.sh and for reference.
#
# Last Updated: January 2026
# =============================================================================

# -----------------------------------------------------------------------------
# VM Identification Outputs
# -----------------------------------------------------------------------------

output "vm_id" {
  description = "Proxmox VM ID (VMID)"
  value       = proxmox_virtual_environment_vm.docker_pool.vm_id
}

output "vm_hostname" {
  description = "VM hostname"
  value       = var.vm_hostname
}

output "vm_node" {
  description = "Proxmox node where the VM is running"
  value       = proxmox_virtual_environment_vm.docker_pool.node_name
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Network Outputs
# -----------------------------------------------------------------------------

output "vm_ip_address" {
  description = "Configured IPv4 address with CIDR"
  value       = var.vm_ip_address
}

output "vm_ipv4_addresses" {
  description = "IPv4 addresses reported by QEMU Guest Agent"
  value       = proxmox_virtual_environment_vm.docker_pool.ipv4_addresses
}

output "vm_mac_addresses" {
  description = "MAC addresses of the VM's network interfaces"
  value       = proxmox_virtual_environment_vm.docker_pool.mac_addresses
}

# -----------------------------------------------------------------------------
# Authentication Outputs
# -----------------------------------------------------------------------------

output "vm_username" {
  description = "Username for VM access"
  value       = var.vm_username
}

output "vm_root_password" {
  description = "Generated password for VM user (use SSH keys preferably)"
  value       = random_password.vm_root_password.result
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Service Outputs
# -----------------------------------------------------------------------------

output "portainer_url" {
  description = "Portainer web UI URL (HTTPS)"
  value       = "https://${trimsuffix(var.vm_ip_address, "/24")}:9443"
}

output "portainer_data_path" {
  description = "Portainer data persistence path on Proxmox host"
  value       = var.portainer_bind_mount_source
}

# -----------------------------------------------------------------------------
# SSH Connection Outputs
# -----------------------------------------------------------------------------

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh ${var.vm_username}@${trimsuffix(var.vm_ip_address, "/24")}"
}

# -----------------------------------------------------------------------------
# Hardware Configuration Outputs
# -----------------------------------------------------------------------------

output "vm_cpu_cores" {
  description = "Number of CPU cores allocated"
  value       = var.vm_cpu_cores
}

output "vm_memory_mb" {
  description = "Dedicated memory in MB"
  value       = var.vm_memory
}

output "vm_disk_size_gb" {
  description = "Boot disk size in GB"
  value       = var.vm_disk_size
}

# -----------------------------------------------------------------------------
# NetBox Registration Outputs
# -----------------------------------------------------------------------------

output "netbox_vm_id" {
  description = "NetBox virtual machine ID"
  value       = netbox_virtual_machine.docker_pool.id
}

output "netbox_ip_id" {
  description = "NetBox IP address ID"
  value       = netbox_ip_address.primary.id
}
