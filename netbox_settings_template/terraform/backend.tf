# =============================================================================
# S3 Backend Configuration for Remote State Storage
# =============================================================================
#
# This configures AWS S3 as the backend for storing Terraform state files.
# Backend configuration CANNOT use variable interpolation due to Terraform
# initialization requirements.
#
# Configuration Methods:
# 1. Backend config file (recommended):
#    tofu init -backend-config=s3.backend.config
#
# 2. Environment variables:
#    export AWS_PROFILE=your-profile
#    export TF_CLI_ARGS_init="-backend-config=s3.backend.config"
#
# 3. Interactive input during init
#
# Security Features:
# - State locking via S3 native locking (use_lockfile = true)
# - Encryption at rest (S3 server-side encryption)
# - State file encryption (see encryption.tf)
# - Version control via S3 versioning
#
# Author: HomeLab Infrastructure
# Last Updated: January 2026
# =============================================================================

terraform {
  backend "s3" {
    # Backend configuration will be provided via s3.backend.config file
    # during initialization: tofu init -backend-config=s3.backend.config
    #
    # This empty block declares we're using S3 backend.
    # All configuration values (bucket, key, region, etc.) must be
    # provided in the s3.backend.config file as variables cannot be used here.
    #
    # IMPORTANT: Variables are NOT allowed in backend blocks!
    # The backend is initialized before variables are evaluated.
  }

  required_providers {
    # NetBox provider for DCIM/IPAM management
    netbox = {
      source  = "e-breuninger/netbox"
      version = ">= 3.0.0"
    }

    # AWS provider for S3 backend
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # Vault provider for secrets management
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0.0"
    }
  }
}
