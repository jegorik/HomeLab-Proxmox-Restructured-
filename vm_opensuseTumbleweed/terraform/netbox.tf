# =============================================================================
# VM OpenSUSE Tumbleweed - NetBox Registration
# =============================================================================

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

resource "netbox_virtual_machine" "tumbleweed_vm" {
  name        = var.vm_hostname
  description = var.vm_description
  cluster_id  = data.netbox_cluster.cluster.id
  device_id   = var.device_id
  site_id     = data.netbox_site.site.id
  tenant_id   = data.netbox_tenant.tenant.id

  vcpus        = var.vm_cpu_cores
  memory_mb    = var.vm_memory_dedicated
  disk_size_mb = (var.vm_boot_disk_size * 1024) + (var.data_disk_size * 1024)

  status = var.vm_status_in_netbox

  comments = <<-EOT
    OpenSUSE Tumbleweed VM
    Managed by OpenTofu
    Proxmox Node: ${data.vault_generic_secret.proxmox_node_name.data["node_name"]}
    VMID: ${var.vm_id}
    Created: ${timestamp()}
    
    Persistence:
    - Data Disk: ${var.data_disk_size} GB
  EOT

  tags = var.vm_tags

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
  virtual_machine_id = netbox_virtual_machine.tumbleweed_vm.id
  name               = var.interface_name

  depends_on = [netbox_virtual_machine.tumbleweed_vm]
}

# -----------------------------------------------------------------------------
# IP Address in NetBox
# -----------------------------------------------------------------------------

resource "netbox_ip_address" "primary" {
  ip_address  = var.vm_ip_address
  status      = var.vm_ip_status_in_netbox
  vrf_id      = data.netbox_vrf.vrf.id
  tenant_id   = data.netbox_tenant.tenant.id
  description = "Primary IP for ${var.vm_hostname}"

  object_type  = var.vm_netbox_object_type
  interface_id = netbox_interface.eth0.id

  depends_on = [netbox_interface.eth0]
}

# -----------------------------------------------------------------------------
# Set Primary IP for VM
# -----------------------------------------------------------------------------

resource "netbox_primary_ip" "tumbleweed_vm" {
  virtual_machine_id = netbox_virtual_machine.tumbleweed_vm.id
  ip_address_id      = netbox_ip_address.primary.id

  depends_on = [netbox_ip_address.primary]
}

# -----------------------------------------------------------------------------
# Virtual Disks in NetBox
# -----------------------------------------------------------------------------

resource "netbox_virtual_disk" "boot_disk" {
  name               = var.disk_name
  description        = var.disk_description
  size_mb            = (var.vm_boot_disk_size * 1024)
  virtual_machine_id = netbox_virtual_machine.tumbleweed_vm.id

  depends_on = [netbox_virtual_machine.tumbleweed_vm]
}

resource "netbox_virtual_disk" "data_disk" {
  name               = var.data_disk_name
  description        = var.data_disk_description
  size_mb            = (var.data_disk_size * 1024)
  virtual_machine_id = netbox_virtual_machine.tumbleweed_vm.id

  depends_on = [netbox_virtual_machine.tumbleweed_vm]
}
