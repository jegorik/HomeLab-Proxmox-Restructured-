# # Uncomment this file and apply with terraform after lxc_netbox_template is deployed
# # =============================================================================
# # LXC NetBox - NetBox Registration
# # =============================================================================
# # Automatically registers the container in NetBox for DCIM/IPAM tracking

# # -----------------------------------------------------------------------------
# # Virtual Machine in NetBox
# # -----------------------------------------------------------------------------

# data "netbox_cluster" "cluster_01" {
#   name = var.cluster_name
# }

# data "netbox_site" "site_01" {
#   name = var.site_name
# }

# data "netbox_tenant" "tenant_01" {
#   name = var.tenant_name
# }

# data "netbox_vrf" "vrf_01" {
#   name = var.vrf_name
# }

# resource "netbox_virtual_machine" "lxc" {
#   name         = var.lxc_hostname
#   description  = var.lxc_description
#   cluster_id   = data.netbox_cluster.cluster_01.id
#   device_id    = var.device_id
#   site_id      = data.netbox_site.site_01.id
#   tenant_id    = data.netbox_tenant.tenant_01.id
#   vcpus        = var.lxc_cpu_cores
#   memory_mb    = var.lxc_memory
#   disk_size_mb = (var.lxc_disk_size * 1024)

#   status = "active"

#   comments = <<-EOT
#     LXC Container deployed by lxc_netbox
#     Proxmox Node: ${data.vault_generic_secret.proxmox_node_name.data["node_name"]}
#     VMID: ${var.lxc_id}
#     Created: ${timestamp()}
#   EOT

#   tags = var.lxc_tags

#   lifecycle {
#     ignore_changes = [
#       comments
#     ]
#   }
# }

# # -----------------------------------------------------------------------------
# # Network Interface in NetBox
# # -----------------------------------------------------------------------------

# resource "netbox_interface" "eth0" {
#   virtual_machine_id = netbox_virtual_machine.lxc.id
#   name               = var.interface_name

#   depends_on = [netbox_virtual_machine.lxc]
# }

# # -----------------------------------------------------------------------------
# # Virtual Disk in NetBox
# # -----------------------------------------------------------------------------

# resource "netbox_virtual_disk" "disk-01" {
#   name               = var.disk_name
#   description        = var.disk_description
#   size_mb            = (var.lxc_disk_size * 1024)
#   virtual_machine_id = netbox_virtual_machine.lxc.id
# }

# # -----------------------------------------------------------------------------
# # IP Address in NetBox
# # -----------------------------------------------------------------------------

# resource "netbox_ip_address" "primary" {
#   ip_address = var.lxc_ip_address
#   status     = "active"
#   vrf_id     = data.netbox_vrf.vrf_01.id

#   object_type  = "virtualization.vminterface"
#   interface_id = netbox_interface.eth0.id

#   description = "${var.lxc_hostname} primary IP"

#   depends_on = [netbox_interface.eth0]
# }

# # Assign IP as primary for the VM
# resource "netbox_primary_ip" "lxc" {
#   virtual_machine_id = netbox_virtual_machine.lxc.id
#   ip_address_id      = netbox_ip_address.primary.id

#   depends_on = [netbox_ip_address.primary]
# }
