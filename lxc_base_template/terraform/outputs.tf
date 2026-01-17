# =============================================================================
# LXC Base Template - Terraform Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Container Information
# -----------------------------------------------------------------------------

output "container_id" {
  description = "LXC container VMID"
  value       = proxmox_virtual_environment_container.lxc.vm_id
}

output "container_hostname" {
  description = "Container hostname"
  value       = var.container_hostname
}

output "container_ip" {
  description = "Container IP address (without CIDR)"
  value       = split("/", var.network_ip)[0]
}

output "container_ip_cidr" {
  description = "Container IP address (with CIDR)"
  value       = var.network_ip
}

# -----------------------------------------------------------------------------
# SSH Access
# -----------------------------------------------------------------------------

output "ssh_user" {
  description = "SSH user for Ansible"
  value       = var.ssh_user
}

output "ssh_port" {
  description = "SSH port"
  value       = 22
}

output "ssh_command" {
  description = "SSH command to access the container"
  value       = "ssh ${var.ssh_user}@${split("/", var.network_ip)[0]}"
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

# -----------------------------------------------------------------------------
# Deployment Summary
# -----------------------------------------------------------------------------

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOT
    
    ╔══════════════════════════════════════════════════════╗
    ║              LXC Container Deployed                  ║
    ╚══════════════════════════════════════════════════════╝
    
    Container:  ${var.container_hostname} (VMID: ${proxmox_virtual_environment_container.lxc.vm_id})
    Node:       ${var.pve_target_node}
    IP:         ${split("/", var.network_ip)[0]}
    
    SSH:        ssh ${var.ssh_user}@${split("/", var.network_ip)[0]}
    
    NetBox:     ${var.netbox_url}/virtualization/virtual-machines/${netbox_virtual_machine.lxc.id}/
    
  EOT
}
