# =============================================================================
# VM Docker Pool - S3 Backend Configuration
# =============================================================================
#
# This file configures the S3 backend for Terraform state storage.
# State is encrypted using Vault Transit engine for security.
#
# Backend Configuration:
# - State stored in S3 bucket with versioning
# - Encryption via Vault Transit engine (configured in s3.backend.config)
# - State locking via DynamoDB (if configured)
#
# Usage:
#   tofu init -backend-config=s3.backend.config
#
# Last Updated: January 2026
# =============================================================================

terraform {
  backend "s3" {
    # Backend configuration is provided via s3.backend.config file
    # This allows for environment-specific configuration without
    # hardcoding sensitive values in version control.
    #
    # Required values in s3.backend.config:
    # - bucket: S3 bucket name
    # - key: State file path (e.g., vm_docker-pool/terraform.tfstate)
    # - region: AWS region
    # - encrypt: Enable server-side encryption
  }
}
