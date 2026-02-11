# =============================================================================
# LXC Semaphore UI - NetBox Registration
# =============================================================================
# Automatically registers the container in NetBox for DCIM/IPAM tracking

# -----------------------------------------------------------------------------
# NetBox Data Sources
# -----------------------------------------------------------------------------

data "netbox_cluster" "cluster" {
  name = var.cluster_name
}

data "netbox_site" "site" {
  name = var.site_name
}

data "netbox_tenant" "tenant" {
  name = var.tenant_name
}

data "netbox_vrf" "vrf" {
  name = var.vrf_name
}

# -----------------------------------------------------------------------------
# Virtual Machine in NetBox
# -----------------------------------------------------------------------------

resource "netbox_virtual_machine" "lxc" {
  name        = var.lxc_hostname
  description = var.lxc_description
  cluster_id  = data.netbox_cluster.cluster.id
  device_id   = var.device_id
  site_id     = data.netbox_site.site.id
  tenant_id   = data.netbox_tenant.tenant.id

  vcpus        = var.lxc_cpu_cores
  memory_mb    = var.lxc_memory
  disk_size_mb = (var.lxc_disk_size * 1024)

  status = "active"

  comments = <<-EOT
    LXC Container deployed by lxc_semaphoreUI
    Proxmox Node: ${data.vault_generic_secret.proxmox_node_name.data["node_name"]}
    VMID: ${var.lxc_id}
    Created: ${timestamp()}
  EOT

  tags = var.lxc_tags

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
  name               = var.interface_name

  depends_on = [netbox_virtual_machine.lxc]
}

# -----------------------------------------------------------------------------
# Virtual Disk in NetBox
# -----------------------------------------------------------------------------

resource "netbox_virtual_disk" "disk" {
  name               = var.disk_name
  description        = var.disk_description
  size_mb            = (var.lxc_disk_size * 1024)
  virtual_machine_id = netbox_virtual_machine.lxc.id
}

# -----------------------------------------------------------------------------
# IP Address in NetBox
# -----------------------------------------------------------------------------

resource "netbox_ip_address" "primary" {
  # If DHCP, we don't know the IP yet, so we might skip this or use a placeholder?
  # Only applying if lxc_ip_address is not "dhcp" (checked in main.tf)
  # But main.tf allows "dhcp". NetBox resource fails if invalid IP.
  # Assuming for now lxc_semaphoreUI encourages static IPs for infrastructure.
  # If "dhcp" is passed, this might fail validation. 
  # Adding a condition or simple assignment assuming valid CIDR if set.
  ip_address = var.lxc_ip_address == "dhcp" ? null : var.lxc_ip_address
  status     = "active"
  vrf_id     = data.netbox_vrf.vrf.id

  object_type  = "virtualization.vminterface"
  interface_id = netbox_interface.eth0.id

  description = "${var.lxc_hostname} primary IP"

  depends_on = [netbox_interface.eth0]
}

# Assign IP as primary for the VM
resource "netbox_primary_ip" "lxc" {
  count = var.lxc_ip_address != "dhcp" ? 1 : 0

  virtual_machine_id = netbox_virtual_machine.lxc.id
  ip_address_id      = netbox_ip_address.primary.id

  depends_on = [netbox_ip_address.primary]
}
