# =============================================================================
# NetBox Settings Template - Terraform Variables
# =============================================================================

# -----------------------------------------------------------------------------
# NetBox Connection
# -----------------------------------------------------------------------------

variable "netbox_url" {
  description = "NetBox server URL"
  type        = string
}

variable "netbox_api_token" {
  description = "NetBox API token"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Organization Data
# -----------------------------------------------------------------------------

variable "regions" {
  description = "Map of regions to create"
  type = map(object({
    description = optional(string)
    slug        = optional(string)
  }))
  default = {}
}

variable "site_groups" {
  description = "Map of site groups to create"
  type = map(object({
    description = optional(string)
    slug        = optional(string)
    parent      = optional(string) # Parent site group slug
  }))
  default = {}
}

variable "sites" {
  description = "Map of sites to create"
  type = map(object({
    status      = string
    region      = optional(string) # Region slug
    group       = optional(string) # Site group slug
    description = optional(string)
    slug        = optional(string)
    facility    = optional(string)
    asn         = optional(list(number))
    timezone    = optional(string)
    latitude    = optional(number)
    longitude   = optional(number)
  }))
  default = {}
}

variable "tenants" {
  description = "Map of tenants to create"
  type = map(object({
    description = optional(string)
    slug        = optional(string)
    group       = optional(string) # Tenant group slug
  }))
  default = {}
}

variable "tenant_groups" {
  description = "Map of tenant groups to create"
  type = map(object({
    description = optional(string)
    slug        = optional(string)
    parent      = optional(string) # Parent tenant group slug
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# IPAM Data
# -----------------------------------------------------------------------------

variable "rirs" {
  description = "Map of Regional Internet Registries"
  type = map(object({
    description = optional(string)
    is_private  = optional(bool, false)
    slug        = optional(string)
  }))
  default = {}
}

variable "aggregates" {
  description = "Map of IP Aggregates"
  type = map(object({
    description = optional(string)
    rir         = string # RIR slug (required)
    tenant      = optional(string)
  }))
  default = {}
}

variable "vrfs" {
  description = "Map of VRFs"
  type = map(object({
    description    = optional(string)
    rd             = optional(string)
    tenant         = optional(string)
    enforce_unique = optional(bool, true)
  }))
  default = {}
}

variable "prefixes" {
  description = "Map of Prefixes"
  type = map(object({
    description = optional(string)
    site        = optional(string) # Site slug
    vrf         = optional(string) # VRF name
    vlan        = optional(number) # VLAN VID (requires lookup logic if used via name)
    tenant      = optional(string) # Tenant slug
    status      = optional(string, "active")
    role        = optional(string) # Role slug
    is_pool     = optional(bool, false)
  }))
  default = {}
}

variable "vlan_groups" {
  description = "Map of VLAN Groups"
  type = map(object({
    description = optional(string)
    site        = optional(string) # Site slug
    slug        = optional(string)
    min_vid     = optional(number, 1)
    max_vid     = optional(number, 4094)
  }))
  default = {}
}

variable "vlans" {
  description = "Map of VLANs"
  type = map(object({
    vid         = number
    site        = optional(string) # Site slug
    group       = optional(string) # VLAN Group slug
    description = optional(string)
    tenant      = optional(string)
    status      = optional(string, "active")
    role        = optional(string) # Role slug
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# DCIM Data
# -----------------------------------------------------------------------------

variable "manufacturers" {
  description = "Map of Manufacturers"
  type = map(object({
    description = optional(string)
    slug        = optional(string)
  }))
  default = {}
}

variable "device_types" {
  description = "Map of Device Types"
  type = map(object({
    manufacturer  = string # Manufacturer slug
    model         = string
    slug          = optional(string)
    part_number   = optional(string)
    u_height      = optional(number, 1)
    is_full_depth = optional(bool, true)
  }))
  default = {}
}

variable "device_roles" {
  description = "Map of Device Roles"
  type = map(object({
    color       = optional(string, "cccccc")
    description = optional(string)
    vm_role     = optional(bool, false)
    slug        = optional(string)
  }))
  default = {}
}

variable "platforms" {
  description = "Map of Platforms"
  type = map(object({
    manufacturer = optional(string) # Manufacturer slug
    description  = optional(string)
    slug         = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Virtualization Data
# -----------------------------------------------------------------------------

variable "cluster_types" {
  description = "Map of Cluster Types"
  type = map(object({
    description = optional(string)
    slug        = optional(string)
  }))
  default = {}
}

variable "cluster_groups" {
  description = "Map of Cluster Groups"
  type = map(object({
    description = optional(string)
    slug        = optional(string)
  }))
  default = {}
}

variable "clusters" {
  description = "Map of Clusters"
  type = map(object({
    type        = string           # Cluster Type slug
    group       = optional(string) # Cluster Group slug
    site        = optional(string)
    description = optional(string)
    status      = optional(string, "active")
    tenant      = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Extras
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Map of Tags to create"
  type = map(object({
    color       = optional(string, "9e9e9e")
    description = optional(string)
  }))
  default = {}
}
