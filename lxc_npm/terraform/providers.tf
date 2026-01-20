# =============================================================================
# Terraform Provider Configuration - Nginx Proxy Manager LXC Container
# =============================================================================
#
# This file configures the Terraform providers required for deploying
# Nginx Proxy Manager in a Proxmox LXC container with S3 state backend.
#
# Providers Used:
# - bpg/proxmox: Proxmox VE management (containers, VMs, storage)
# - hashicorp/aws: S3 backend for state storage
# - hashicorp/vault: Secret management
# - hashicorp/random: Secure password generation
#
# Last Updated: January 2026
# =============================================================================

# -----------------------------------------------------------------------------
# Vault Provider Configuration
# -----------------------------------------------------------------------------

provider "vault" {
  # Vault server address
  address = var.vault_address

  # Skip TLS verification (set to false in production with valid certs)
  skip_tls_verify = var.vault_skip_tls_verify

  skip_child_token = true

  # Authentication using token from VAULT_TOKEN environment variable
  # Token is set by sourcing vault_init.sh which authenticates via userpass
  # and exports VAULT_TOKEN to the environment
}

# -----------------------------------------------------------------------------
# Vault Data Sources - Retrieve Secrets from Vault
# -----------------------------------------------------------------------------
# Note: These use data sources because they're referenced in provider configuration
# and resource attributes that persist in state. Ephemeral resources are only
# supported in write-only contexts (provisioners, sensitive provider settings).

# Retrieve Proxmox endpoint URL from Vault
data "vault_generic_secret" "proxmox_endpoint" {
  path = var.proxmox_endpoint_vault_path
}

# Retrieve Proxmox node name from Vault
data "vault_generic_secret" "proxmox_node_name" {
  path = var.proxmox_node_name_vault_path
}

# Retrieve Proxmox user from Vault
data "vault_generic_secret" "proxmox_user" {
  path = var.proxmox_user_name_vault_path
}

data "vault_generic_secret" "proxmox_root" {
  path = var.proxmox_root_name_vault_path
}

# Retrieve SSH root public key from Vault
data "vault_generic_secret" "root_ssh_public_key" {
  path = var.root_ssh_public_key_path
}

# Retrieve SSH Ansible public key from Vault
data "vault_generic_secret" "ansible_ssh_public_key" {
  path = var.ansible_ssh_public_key_path
}

# Retrieve S3 bucket name from Vault
data "vault_generic_secret" "s3_bucket_name" {
  path = var.s3_bucket_name_vault_path
}

# Retrieve Proxmox API token from Vault (ephemeral - not stored in state)
ephemeral "vault_kv_secret_v2" "proxmox_api_token" {
  mount = var.ephemeral_vault_mount_path
  name  = var.proxmox_api_token_vault_path
}

ephemeral "vault_kv_secret_v2" "netbox_api_token" {
  mount = var.ephemeral_vault_mount_path
  name  = var.netbox_api_token_vault_path
}

ephemeral "vault_kv_secret_v2" "proxmox_root_password" {
  mount = var.ephemeral_vault_mount_path
  name  = var.proxmox_root_password_vault_path
}

# Retrieve SSH root private key from Vault (ephemeral - not stored in state)
ephemeral "vault_kv_secret_v2" "root_ssh_private_key" {
  mount = var.ephemeral_vault_mount_path
  name  = var.root_ssh_private_key_path
}

# -----------------------------------------------------------------------------
# Proxmox Provider Configuration
# -----------------------------------------------------------------------------

provider "proxmox" {
  # Proxmox VE API endpoint URL (from Vault)
  endpoint = data.vault_generic_secret.proxmox_endpoint.data["url"]

  # Authentication via username/password (required for bind mounts)
  username = data.vault_generic_secret.proxmox_root.data["username"]
  password = ephemeral.vault_kv_secret_v2.proxmox_root_password.data["password"]

  # Skip TLS verification (set to false in production with valid certs)
  insecure = var.connection_insecure

  # SSH configuration for operations requiring direct host access
  ssh {
    agent    = var.ssh_agent_enabled
    username = data.vault_generic_secret.proxmox_root.data["username"]
  }
}

# -----------------------------------------------------------------------------
# AWS Provider Configuration (for S3 Backend)
# -----------------------------------------------------------------------------

provider "aws" {
  # AWS region for S3 backend and resource deployment
  region = var.aws_region
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
