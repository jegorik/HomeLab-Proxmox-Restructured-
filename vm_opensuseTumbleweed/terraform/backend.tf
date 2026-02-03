# =============================================================================
# VM OpenSUSE Tumbleweed - State Backend Configuration
# =============================================================================
#
# This file configures where Terraform/OpenTofu state is stored.
# For remote state (recommended for production), use S3 backend.
#
# Usage with S3:
#   cp s3.backend.config.template s3.backend.config
#   Edit s3.backend.config with your bucket/region/key
#   tofu init -backend-config=s3.backend.config
#
# Without s3.backend.config, state is stored locally (default).
# =============================================================================

terraform {
  backend "s3" {
    # Backend configuration is provided via s3.backend.config file.
    # Required values in s3.backend.config: bucket, key, region, encrypt
  }
}
