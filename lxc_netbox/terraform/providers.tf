# =============================================================================
# Terraform Provider Configuration - HashiCorp Vault LXC Container
# =============================================================================
#
# This file configures the Terraform providers required for deploying a
# HashiCorp Vault instance in a Proxmox LXC container with S3 state backend.
#
# Providers Used:
# - bpg/proxmox: Proxmox VE management (containers, VMs, storage)
# - hashicorp/aws: S3 backend for state storage
# - hashicorp/random: Secure password generation
#
# Provider: bpg/proxmox
# Documentation: https://registry.terraform.io/providers/bpg/proxmox/latest/docs
# GitHub: https://github.com/bpg/terraform-provider-proxmox
#
# Proxmox VE Compatibility:
#   - Tested with Proxmox VE 8.x
#   - Compatible with Proxmox VE 7.4+
#   - PVE 9.1+ supports OCI images for LXC (not used in this config)
#
# Authentication Methods (in order of preference):
#   1. API Token (recommended for most operations) - Set via proxmox_api_token variable
#   2. Username/Password (REQUIRED for bind mounts) - Set via pve_root_user/pve_root_password
#
# IMPORTANT: Why root@pam with Password is Required for Bind Mounts
# ------------------------------------------------------------------
# When using bind mounts (mount_point blocks), you MUST authenticate with root@pam
# credentials (username + password). API tokens will NOT work, even with full permissions.
#
# Technical Reasons:
# 1. Bind mounts require direct filesystem operations on the Proxmox host
# 2. The Proxmox API needs elevated privileges to modify /etc/pve/lxc/*.conf
# 3. API tokens have security restrictions that prevent certain privileged operations
# 4. The bpg/proxmox provider specifically requires password auth for mount operations
#
# This is a known limitation documented in:
# - Provider GitHub: https://github.com/bpg/terraform-provider-proxmox/issues/836
# - Provider GitHub: https://github.com/bpg/terraform-provider-proxmox/issues/450
# - Proxmox Docs: https://pve.proxmox.com/wiki/Linux_Container#pct_mount_points
#
# Security Implications:
# - Store password in a secure file with restricted permissions (chmod 600)
# - Consider using environment variables: export TF_VAR_pve_root_password="..."
# - Use a dedicated automation password, not your interactive root password
# - Rotate the password periodically
# - Restrict SSH access and use key-based auth for shell access
#
# Alternative for Better Security:
# - Use NFS/CIFS mounts instead of bind mounts (works with API tokens)
# - Use cloud-init volumes for data injection
# - Use network storage backends (iSCSI, Ceph, NFS)
#
# Required Proxmox Permissions for API Token (LXC):
#   Path: /
#   - Datastore.AllocateSpace (allocate disk space)
#   - Datastore.AllocateTemplate (download/use templates)
#   - Datastore.Audit (view storage)
#   - SDN.Use (use software-defined networking)
#   - Sys.Audit (view system info)
#   - Sys.Console (required for remote-exec provisioner)
#   - VM.Allocate (create new containers)
#   - VM.Audit (view containers)
#   - VM.Config.* (all config permissions)
#   - VM.PowerMgmt (start/stop/restart)
#
# API Token Creation:
#   Proxmox GUI -> Datacenter -> Permissions -> API Tokens -> Add
#   Format: user@realm!token_id
#
# Security Best Practices:
#   - Use API tokens with minimal required permissions (principle of least privilege)
#   - Store tokens in environment variables or secret managers (not in version control)
#   - Enable TLS verification in production (set insecure = false)
#   - Use SSH agent for secure key management
#   - Rotate API tokens periodically
#   - Use separate tokens for different projects/environments
#
# Author: HomeLab Infrastructure
# Provider Versions: proxmox 0.89.1, aws 6.26.0, random 3.6.x
# Last Updated: January 2025
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

# Retrieve Proxmox API token from Vault
ephemeral "vault_kv_secret_v2" "proxmox_api_token" {
  mount = var.ephemeral_vault_mount_path
  name  = var.proxmox_api_token_vault_path
}

ephemeral "vault_kv_secret_v2" "proxmox_root_password" {
  mount = var.ephemeral_vault_mount_path
  name  = var.proxmox_root_password_vault_path
}

# Retrieve SSH root private key from Vault
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

  # API token in format: user@realm!token_id=secret (from Vault)
  # api_token = data.vault_generic_secret.proxmox_api_token.data["token"]
  # api_token = ephemeral.vault_kv_secret_v2.proxmox_api_token.data["token"]
  username = data.vault_generic_secret.proxmox_root.data["username"]
  password = ephemeral.vault_kv_secret_v2.proxmox_root_password.data["password"]

  # Skip TLS verification (set to false in production with valid certs)
  insecure = var.connection_insecure

  # SSH configuration for operations requiring direct host access
  # (e.g., container exec, template downloads)
  ssh {
    agent    = var.ssh_agent_enabled
    username = data.vault_generic_secret.proxmox_root.data["username"]
  }
}

provider "aws" {
  # AWS region for S3 backend and resource deployment
  # Choose region closest to your infrastructure for better performance
  # Common regions:
  #   - us-east-1 (N. Virginia)
  #   - eu-west-1 (Ireland)
  #   - eu-central-1 (Frankfurt)
  #   - ap-southeast-1 (Singapore)
  region = var.aws_region

  # Optional: AWS CLI profile to use
  # Uncomment and set var.aws_profile in terraform.tfvars
  # profile = var.aws_profile
}

