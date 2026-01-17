# =============================================================================
# NetBox Settings Template - Providers
# =============================================================================

provider "netbox" {
  server_url = var.netbox_url
  api_token  = var.netbox_api_token

  # Skip TLS verification for self-signed certs (e.g. in local Proxmox labs)
  allow_insecure_https = true
}
