# =============================================================================
# VM OpenSUSE Tumbleweed - Outputs
# =============================================================================

output "vm_name" {
  description = "The name of the VM"
  value       = proxmox_virtual_environment_vm.tumbleweed_vm[0].name
}

output "vm_id" {
  description = "The ID of the VM"
  value       = proxmox_virtual_environment_vm.tumbleweed_vm[0].id
}

output "vm_ip_address" {
  description = "The primary IPv4 address of the VM"
  value       = local.vm_ip
}

output "ansible_user_name" {
  description = "The username for Ansible connection"
  value       = var.ansible_user_name
}

output "vm_username" {
  description = "The username for root user"
  value       = var.vm_username
}

output "target_user_uid" {
  description = "The UID for the target user"
  value       = var.target_user_uid
}

output "vm_root_password" {
  description = "Generated password for VM user (use SSH keys preferably)"
  value       = random_password.vm_root_password.result
  sensitive   = true
}
