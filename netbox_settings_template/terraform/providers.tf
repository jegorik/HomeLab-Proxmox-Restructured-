# =============================================================================
# NetBox Settings Template - Providers
# =============================================================================

# -----------------------------------------------------------------------------
# Vault Provider Configuration  
# -----------------------------------------------------------------------------

provider "vault" {
  address          = var.vault_address
  skip_tls_verify  = var.vault_skip_tls_verify
  skip_child_token = true
  # Token from VAULT_TOKEN environment variable
}

# -----------------------------------------------------------------------------
# AWS Provider Configuration (for S3 Backend)
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
  # Credentials via AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY environment variables
  # or via Vault AWS secrets engine dynamic credentials
}

# -----------------------------------------------------------------------------
# Vault Data Source - Retrieve NetBox API Token
# -----------------------------------------------------------------------------

ephemeral "vault_kv_secret_v2" "netbox_api_token" {
  mount = var.vault_kv_mount
  name  = var.netbox_api_token_vault_path
}

# -----------------------------------------------------------------------------
# NetBox Provider Configuration
# -----------------------------------------------------------------------------

provider "netbox" {
  server_url = var.netbox_url
  api_token  = ephemeral.vault_kv_secret_v2.netbox_api_token.data["token"]

  # Skip TLS verification for self-signed certs (e.g. in local Proxmox labs)
  allow_insecure_https = var.netbox_insecure
}
