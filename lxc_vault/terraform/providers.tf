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
# Last Updated: December 2025
# =============================================================================

# -----------------------------------------------------------------------------
# Proxmox Provider Configuration
# -----------------------------------------------------------------------------

provider "proxmox" {
  # Proxmox VE API endpoint URL
  endpoint = var.proxmox_endpoint

  # API token in format: user@realm!token_id=secret
  username = var.pve_root_user
  password = var.pve_root_password

  # Skip TLS verification (set to false in production with valid certs)
  insecure = var.connection_insecure

  # SSH configuration for operations requiring direct host access
  # (e.g., container exec, template downloads)
  ssh {
    agent    = var.ssh_agent_enabled
    username = var.proxmox_ssh_user
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

# -----------------------------------------------------------------------------
# NetBox Provider
# -----------------------------------------------------------------------------

provider "netbox" {
  server_url = var.netbox_url
  api_token  = local.netbox_token

  # Skip TLS verification for self-signed certs
  allow_insecure_https = true
}
