# =============================================================================
# LXC Semaphore UI - Terraform Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Container Information
# -----------------------------------------------------------------------------

output "lxc_id" {
  description = "LXC container VMID"
  value       = proxmox_virtual_environment_container.semaphore.vm_id
}

output "lxc_hostname" {
  description = "Container hostname"
  value       = var.lxc_hostname
}

output "lxc_ip_address" {
  description = "Container IP address (without CIDR)"
  value       = split("/", var.lxc_ip_address)[0]
}

output "lxc_ip_cidr" {
  description = "Container IP address (with CIDR)"
  value       = var.lxc_ip_address
}

# -----------------------------------------------------------------------------
# SSH Access
# -----------------------------------------------------------------------------

output "ssh_user" {
  description = "SSH user for Ansible"
  value       = var.ansible_user_name
}

output "ssh_port" {
  description = "SSH port"
  value       = 22
}

output "ssh_command" {
  description = "SSH command to access the container"
  value       = "ssh ${var.ansible_user_name}@${split("/", var.lxc_ip_address)[0]}"
}

# -----------------------------------------------------------------------------
# NetBox Information
# -----------------------------------------------------------------------------

output "netbox_vm_id" {
  description = "NetBox virtual machine ID"
  value       = netbox_virtual_machine.lxc.id
}

output "netbox_vm_url" {
  description = "NetBox virtual machine URL"
  value       = "${var.netbox_url}/virtualization/virtual-machines/${netbox_virtual_machine.lxc.id}/"
}

output "root_password" {
  value     = random_password.root_password.result
  sensitive = true
}

# -----------------------------------------------------------------------------
# Deployment Summary
# -----------------------------------------------------------------------------

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOT
    
    ╔══════════════════════════════════════════════════════╗
    ║              LXC Container Deployed                  ║
    ╚══════════════════════════════════════════════════════╝
    
    Container:  ${var.lxc_hostname} (VMID: ${proxmox_virtual_environment_container.semaphore.vm_id})
    IP:         ${split("/", var.lxc_ip_address)[0]}
    
    SSH:        ssh ${var.ansible_user_name}@${split("/", var.lxc_ip_address)[0]}
    
    NetBox:     ${var.netbox_url}/virtualization/virtual-machines/${netbox_virtual_machine.lxc.id}/
    
  EOT
}
