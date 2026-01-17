# =============================================================================
# NetBox Settings Template - Versions
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    netbox = {
      source  = "e-breuninger/netbox"
      version = ">= 3.0.0"
    }
  }
}
