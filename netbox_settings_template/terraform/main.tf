# =============================================================================
# NetBox Settings Template - Main Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Organization
# -----------------------------------------------------------------------------

resource "netbox_region" "all" {
  for_each = var.regions

  name        = each.key
  slug        = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  description = each.value.description
}

resource "netbox_site_group" "all" {
  for_each = var.site_groups

  name        = each.key
  slug        = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  description = each.value.description
  parent_id   = each.value.parent != null ? netbox_site_group.all[each.value.parent].id : null
}

resource "netbox_site" "all" {
  for_each = var.sites

  name        = each.key
  slug        = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  status      = each.value.status
  description = each.value.description
  region_id   = each.value.region != null ? netbox_region.all[each.value.region].id : null
  group_id    = each.value.group != null ? netbox_site_group.all[each.value.group].id : null
  facility    = each.value.facility
  asn_ids     = []
  timezone    = each.value.timezone
  latitude    = each.value.latitude
  longitude   = each.value.longitude
}

resource "netbox_tenant_group" "all" {
  for_each = var.tenant_groups

  name        = each.key
  slug        = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  description = each.value.description
  parent_id   = each.value.parent != null ? netbox_tenant_group.all[each.value.parent].id : null
}

resource "netbox_tenant" "all" {
  for_each = var.tenants

  name        = each.key
  slug        = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  description = each.value.description
  group_id    = each.value.group != null ? netbox_tenant_group.all[each.value.group].id : null
}

# -----------------------------------------------------------------------------
# 2. IPAM
# -----------------------------------------------------------------------------

resource "netbox_rir" "all" {
  for_each = var.rirs

  name        = each.key
  slug        = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  description = each.value.description
  is_private  = each.value.is_private
}

resource "netbox_aggregate" "all" {
  for_each = var.aggregates

  prefix      = each.key
  description = each.value.description
  rir_id      = netbox_rir.all[each.value.rir].id
  tenant_id   = each.value.tenant != null ? netbox_tenant.all[each.value.tenant].id : null
}

resource "netbox_vrf" "all" {
  for_each = var.vrfs

  name        = each.key
  rd          = each.value.rd
  description = each.value.description
  tenant_id   = each.value.tenant != null ? netbox_tenant.all[each.value.tenant].id : null
}

resource "netbox_prefix" "all" {
  for_each = var.prefixes

  prefix      = each.key
  description = each.value.description
  site_id     = each.value.site != null ? netbox_site.all[each.value.site].id : null
  vrf_id      = each.value.vrf != null ? netbox_vrf.all[each.value.vrf].id : null
  tenant_id   = each.value.tenant != null ? netbox_tenant.all[each.value.tenant].id : null
  status      = each.value.status
  is_pool     = each.value.is_pool

  # Note: role_id would need a netbox_role data source or resource lookup
}

resource "netbox_vlan_group" "all" {
  for_each = var.vlan_groups

  name        = each.key
  slug        = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  description = each.value.description
  # site_id is unexpected, replacing with scope logic if possible or commenting out
  # site_id     = each.value.site != null ? netbox_site.all[each.value.site].id : null

  # min_vid/max_vid replaced by vid_ranges
  vid_ranges = [[each.value.min_vid, each.value.max_vid]]
}

resource "netbox_vlan" "all" {
  for_each = var.vlans

  vid         = each.value.vid
  name        = each.key
  site_id     = each.value.site != null ? netbox_site.all[each.value.site].id : null
  group_id    = each.value.group != null ? netbox_vlan_group.all[each.value.group].id : null
  description = each.value.description
  tenant_id   = each.value.tenant != null ? netbox_tenant.all[each.value.tenant].id : null
  status      = each.value.status
}

# -----------------------------------------------------------------------------
# 3. DCIM
# -----------------------------------------------------------------------------

resource "netbox_manufacturer" "all" {
  for_each = var.manufacturers

  name = each.key
  slug = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  # description = each.value.description # Unexpected attribute
}

resource "netbox_device_type" "all" {
  for_each = var.device_types

  model           = each.value.model
  slug            = coalesce(each.value.slug, replace(lower(each.value.model), " ", "-"))
  manufacturer_id = netbox_manufacturer.all[each.value.manufacturer].id
  part_number     = each.value.part_number
  u_height        = each.value.u_height
  is_full_depth   = each.value.is_full_depth
}

resource "netbox_device_role" "all" {
  for_each = var.device_roles

  name        = each.key
  slug        = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  color_hex   = each.value.color
  description = each.value.description
  vm_role     = each.value.vm_role
}

resource "netbox_platform" "all" {
  for_each = var.platforms

  name            = each.key
  slug            = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  manufacturer_id = each.value.manufacturer != null ? netbox_manufacturer.all[each.value.manufacturer].id : null
  # description     = each.value.description # Unexpected attribute
}

# -----------------------------------------------------------------------------
# 4. Virtualization
# -----------------------------------------------------------------------------

resource "netbox_cluster_type" "all" {
  for_each = var.cluster_types

  name = each.key
  slug = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  # description = each.value.description # Unexpected attribute
}

resource "netbox_cluster_group" "all" {
  for_each = var.cluster_groups

  name        = each.key
  slug        = coalesce(each.value.slug, replace(lower(each.key), " ", "-"))
  description = each.value.description
}

resource "netbox_cluster" "all" {
  for_each = var.clusters

  name             = each.key
  cluster_type_id  = netbox_cluster_type.all[each.value.type].id
  cluster_group_id = each.value.group != null ? netbox_cluster_group.all[each.value.group].id : null
  site_id          = each.value.site != null ? netbox_site.all[each.value.site].id : null
  description      = each.value.description
  # status           = each.value.status # Unexpected attribute
  tenant_id = each.value.tenant != null ? netbox_tenant.all[each.value.tenant].id : null
}

# -----------------------------------------------------------------------------
# 5. Extras
# -----------------------------------------------------------------------------

resource "netbox_tag" "all" {
  for_each = var.tags

  name        = each.key
  slug        = replace(lower(each.key), " ", "-")
  color_hex   = each.value.color
  description = each.value.description
}
