# =============================================================================
# VM OpenSUSE Tumbleweed - Provider Configuration
# =============================================================================
# This file configures the Terraform providers required for deploying
# VMs in a Proxmox environment with S3 state backend.
#
# Providers Used:
# - bpg/proxmox: Proxmox VE management (VMs, storage)
# - hashicorp/aws: S3 backend for state storage
# - hashicorp/vault: Secret management
# - hashicorp/random: Secure password generation
# - e-breuninger/netbox: DCIM/IPAM registration
#
# Last Updated: January 2026
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.94.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "6.30.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = "5.6.0"
    }

    netbox = {
      source  = "e-breuninger/netbox"
      version = "5.1.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.8.1"
    }
  }
}

# -----------------------------------------------------------------------------
# Vault Generic Secrets (Persist in State)
# -----------------------------------------------------------------------------

# Retrieve Proxmox endpoint URL from Vault
data "vault_generic_secret" "proxmox_endpoint" {
  path = var.proxmox_endpoint_vault_path
}

# Retrieve Proxmox node name from Vault
data "vault_generic_secret" "proxmox_node_name" {
  path = var.proxmox_node_name_vault_path
}

# Retrieve Proxmox root user from Vault
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

# -----------------------------------------------------------------------------
# Vault Ephemeral Secrets (Do Not Persist in State)
# -----------------------------------------------------------------------------

# Retrieve Proxmox API token from Vault
ephemeral "vault_kv_secret_v2" "proxmox_api_token" {
  mount = var.ephemeral_vault_mount_path
  name  = var.proxmox_api_token_vault_path
}

# Retrieve NetBox API token from Vault
ephemeral "vault_kv_secret_v2" "netbox_api_token" {
  mount = var.ephemeral_vault_mount_path
  name  = var.netbox_api_token_vault_path
}

# Retrieve Proxmox root password from Vault
ephemeral "vault_kv_secret_v2" "proxmox_root_password" {
  mount = var.ephemeral_vault_mount_path
  name  = var.proxmox_root_password_vault_path
}

# Retrieve SSH root private key from Vault (for provisioners)
ephemeral "vault_kv_secret_v2" "root_ssh_private_key" {
  mount = var.ephemeral_vault_mount_path
  name  = var.root_ssh_private_key_path
}

provider "vault" {
  address          = var.vault_address
  skip_tls_verify  = var.vault_skip_tls_verify
  skip_child_token = true
}

provider "aws" {
  region = var.aws_region
}

provider "proxmox" {
  # Proxmox VE API endpoint URL (from Vault)
  endpoint = data.vault_generic_secret.proxmox_endpoint.data["url"]
  username = data.vault_generic_secret.proxmox_root.data["username"]
  password = ephemeral.vault_kv_secret_v2.proxmox_root_password.data["password"]

  # Skip TLS verification (set to false in production with valid certs)
  insecure = var.connection_insecure

  # SSH configuration for operations requiring direct host access
  ssh {
    agent       = var.ssh_agent_enabled
    username    = split("@", data.vault_generic_secret.proxmox_root.data["username"])[0]
    private_key = ephemeral.vault_kv_secret_v2.root_ssh_private_key.data["key"]
  }
}

provider "netbox" {
  server_url           = var.netbox_url
  api_token            = ephemeral.vault_kv_secret_v2.netbox_api_token.data["token"]
  allow_insecure_https = var.netbox_insecure
}
