# =============================================================================
# NetBox Settings Template - Outputs
# =============================================================================

output "sites_created" {
  description = "Map of sites created"
  value       = { for k, v in netbox_site.all : k => v.id }
}

output "prefixes_created" {
  description = "Map of prefixes created"
  value       = { for k, v in netbox_prefix.all : k => v.id }
}

output "deployment_summary" {
  value = <<-EOT
    
    ╔══════════════════════════════════════════════════════╗
    ║            NetBox Configuration Applied              ║
    ╚══════════════════════════════════════════════════════╝
    
    Sites:          ${length(netbox_site.all)}
    Prefixes:       ${length(netbox_prefix.all)}
    VLANs:          ${length(netbox_vlan.all)}
    Device Types:   ${length(netbox_device_type.all)}
    
  EOT
}
