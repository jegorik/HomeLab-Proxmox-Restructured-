# =============================================================================
# Nginx Proxy Manager LXC Container - Terraform Providers
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.50.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0.0"
    }

    netbox = {
      source  = "e-breuninger/netbox"
      version = ">= 3.0.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Vault Provider
# -----------------------------------------------------------------------------

provider "vault" {
  address = var.vault_address
  token   = var.vault_token != "" ? var.vault_token : null

  # Skip TLS verification for self-signed certs (not recommended for production)
  skip_tls_verify = true
}

# -----------------------------------------------------------------------------
# Fetch Secrets from Vault
# -----------------------------------------------------------------------------

data "vault_kv_secret_v2" "proxmox" {
  mount = "secret"
  name  = var.vault_pve_secret_path
}

data "vault_kv_secret_v2" "netbox" {
  mount = "secret"
  name  = var.vault_netbox_secret_path
}

# Use Vault secrets or fallback to variables
locals {
  pve_password = var.pve_root_password != "" ? var.pve_root_password : data.vault_kv_secret_v2.proxmox.data["password"]
  netbox_token = var.netbox_api_token != "" ? var.netbox_api_token : data.vault_kv_secret_v2.netbox.data["api_token"]
}

# -----------------------------------------------------------------------------
# Proxmox Provider
# -----------------------------------------------------------------------------

provider "proxmox" {
  endpoint = var.pve_api_url
  username = "root@pam"
  password = local.pve_password

  insecure = true

  ssh {
    agent = true
  }
}

# -----------------------------------------------------------------------------
# NetBox Provider
# -----------------------------------------------------------------------------

provider "netbox" {
  server_url = var.netbox_url
  api_token  = local.netbox_token

  # Skip TLS verification for self-signed certs
  allow_insecure_https = true
}
