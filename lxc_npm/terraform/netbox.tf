# =============================================================================
# Nginx Proxy Manager LXC Container - NetBox Registration
# =============================================================================
# Automatically registers the container in NetBox for DCIM/IPAM tracking

# -----------------------------------------------------------------------------
# Virtual Machine in NetBox
# -----------------------------------------------------------------------------

resource "netbox_virtual_machine" "lxc" {
  name       = var.container_hostname
  cluster_id = var.netbox_cluster_id
  site_id    = var.netbox_site_id

  vcpus        = var.container_cores
  memory_mb    = var.container_memory
  disk_size_mb = var.container_disk_size

  status = "active"

  comments = <<-EOT
    Nginx Proxy Manager LXC Container
    Proxmox Node: ${var.pve_target_node}
    VMID: ${var.container_id}
    Created: ${timestamp()}
  EOT

  tags = var.tags

  lifecycle {
    ignore_changes = [
      comments
    ]
  }
}

# -----------------------------------------------------------------------------
# Network Interface in NetBox
# -----------------------------------------------------------------------------

resource "netbox_interface" "eth0" {
  virtual_machine_id = netbox_virtual_machine.lxc.id
  name               = "eth0"

  depends_on = [netbox_virtual_machine.lxc]
}

# -----------------------------------------------------------------------------
# IP Address in NetBox
# -----------------------------------------------------------------------------

resource "netbox_ip_address" "primary" {
  ip_address = var.network_ip
  status     = "active"

  object_type  = "virtualization.vminterface"
  interface_id = netbox_interface.eth0.id

  description = "${var.container_hostname} primary IP"

  depends_on = [netbox_interface.eth0]
}

# Assign IP as primary for the VM
resource "netbox_primary_ip" "lxc" {
  virtual_machine_id = netbox_virtual_machine.lxc.id
  ip_address_id      = netbox_ip_address.primary.id

  depends_on = [netbox_ip_address.primary]
}
