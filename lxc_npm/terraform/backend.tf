# =============================================================================
# Nginx Proxy Manager LXC Container - State Backend Configuration
# =============================================================================
# This file configures where Terraform state is stored and required providers.
#
# Last Updated: January 2026
# =============================================================================

# -----------------------------------------------------------------------------
# Required Providers
# -----------------------------------------------------------------------------

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

    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }

  # ---------------------------------------------------------------------------
  # S3 Backend Configuration
  # ---------------------------------------------------------------------------
  # State is stored in S3 with encryption and locking.
  # Run: tofu init -backend-config=s3.backend.config

  backend "s3" {}
}
