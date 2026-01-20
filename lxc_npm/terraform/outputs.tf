# =============================================================================
# Nginx Proxy Manager LXC Container - Terraform Outputs
# =============================================================================
#
# Last Updated: January 2026
# =============================================================================

# -----------------------------------------------------------------------------
# Container Information
# -----------------------------------------------------------------------------

output "lxc_id" {
  description = "LXC container VMID"
  value       = proxmox_virtual_environment_container.npm.vm_id
}

output "lxc_hostname" {
  description = "Container hostname"
  value       = var.lxc_hostname
}

output "lxc_ip_address" {
  description = "Container IP address (without CIDR)"
  value       = local.container_ip
}

output "lxc_node" {
  description = "Proxmox node where container is deployed"
  value       = data.vault_generic_secret.proxmox_node_name.data["node_name"]
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Credentials (Sensitive)
# -----------------------------------------------------------------------------

output "lxc_root_password" {
  description = "Root password for the container"
  value       = random_password.root_password.result
  sensitive   = true
}

# -----------------------------------------------------------------------------
# SSH Access
# -----------------------------------------------------------------------------

output "ssh_user" {
  description = "SSH user for Ansible"
  value       = var.ansible_user_name
}

output "ssh_command" {
  description = "SSH command to access the container"
  value       = "ssh ${var.ansible_user_name}@${local.container_ip}"
}

output "ssh_command_root" {
  description = "SSH command to access container as root"
  value       = "ssh root@${local.container_ip}"
}

# -----------------------------------------------------------------------------
# NPM Access
# -----------------------------------------------------------------------------

output "npm_admin_url" {
  description = "Nginx Proxy Manager admin UI URL"
  value       = "http://${local.container_ip}:${var.npm_admin_port}"
}

output "npm_http_url" {
  description = "HTTP proxy URL"
  value       = "http://${local.container_ip}:${var.npm_http_port}"
}

output "npm_https_url" {
  description = "HTTPS proxy URL"
  value       = "https://${local.container_ip}:${var.npm_https_port}"
}

# -----------------------------------------------------------------------------
# Deployment Summary
# -----------------------------------------------------------------------------

output "deployment_summary" {
  description = "Deployment summary"
  value       = <<-EOT
    
    ╔══════════════════════════════════════════════════════╗
    ║           Nginx Proxy Manager Deployed               ║
    ╚══════════════════════════════════════════════════════╝
    
    Container:  ${var.lxc_hostname} (VMID: ${proxmox_virtual_environment_container.npm.vm_id})
    IP:         ${local.container_ip}
    
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    NPM Admin:  http://${local.container_ip}:${var.npm_admin_port}
    
    Default Login:
      Email:    admin@example.com
      Password: changeme
    
    ⚠️  CHANGE DEFAULT PASSWORD IMMEDIATELY!
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    SSH:        ssh ${var.ansible_user_name}@${local.container_ip}
    
  EOT
}
