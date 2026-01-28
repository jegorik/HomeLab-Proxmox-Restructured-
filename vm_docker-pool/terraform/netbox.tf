# =============================================================================
# VM Docker Pool - NetBox Registration
# =============================================================================
# Automatically registers the VM in NetBox for DCIM/IPAM tracking

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

resource "netbox_virtual_machine" "docker_pool" {
  name        = var.vm_hostname
  description = var.vm_description
  cluster_id  = data.netbox_cluster.cluster.id
  device_id   = var.device_id
  site_id     = data.netbox_site.site.id
  tenant_id   = data.netbox_tenant.tenant.id

  vcpus        = var.vm_cpu_cores
  memory_mb    = var.vm_memory
  disk_size_mb = (var.vm_disk_size * 1024)

  status = "active"

  comments = <<-EOT
    Ubuntu Server 24.04.3 LTS VM with Docker and Portainer
    Deployed by vm_docker-pool OpenTofu module
    Proxmox Node: ${data.vault_generic_secret.proxmox_node_name.data["node_name"]}
    VMID: ${var.vm_id}
    Created: ${timestamp()}
    
    Services:
    - Docker CE with Docker Compose
    - Portainer CE (HTTPS: 9443)
    
    Bind Mounts:
    - Portainer data: ${var.portainer_bind_mount_source}
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
  virtual_machine_id = netbox_virtual_machine.docker_pool.id
  name               = var.interface_name

  depends_on = [netbox_virtual_machine.docker_pool]
}

# -----------------------------------------------------------------------------
# IP Address in NetBox
# -----------------------------------------------------------------------------

resource "netbox_ip_address" "primary" {
  ip_address  = var.vm_ip_address
  status      = "active"
  vrf_id      = data.netbox_vrf.vrf.id
  tenant_id   = data.netbox_tenant.tenant.id
  description = "Primary IP for ${var.vm_hostname}"

  object_type  = "virtualization.vminterface"
  interface_id = netbox_interface.eth0.id

  depends_on = [netbox_interface.eth0]
}

# -----------------------------------------------------------------------------
# Set Primary IP for VM
# -----------------------------------------------------------------------------

resource "netbox_primary_ip" "docker_pool" {
  virtual_machine_id = netbox_virtual_machine.docker_pool.id
  ip_address_id      = netbox_ip_address.primary.id

  depends_on = [netbox_ip_address.primary]
}

# -----------------------------------------------------------------------------
# Virtual Disk in NetBox
# -----------------------------------------------------------------------------

resource "netbox_virtual_disk" "boot_disk" {
  name               = var.disk_name
  description        = var.disk_description
  size_mb            = (var.vm_disk_size * 1024)
  virtual_machine_id = netbox_virtual_machine.docker_pool.id

  depends_on = [netbox_virtual_machine.docker_pool]
}
