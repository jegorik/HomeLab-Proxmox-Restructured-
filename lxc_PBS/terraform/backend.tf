# =============================================================================
# LXC PBS - State Backend Configuration
# =============================================================================
# This file configures where Terraform state is stored.
# Uncomment and configure ONE backend option.

# -----------------------------------------------------------------------------
# Option 1: Local Backend (Default)
# -----------------------------------------------------------------------------
# State is stored locally. Good for development, not for teams.

# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

# -----------------------------------------------------------------------------
# Option 2: S3 Backend (Recommended for Production)
# -----------------------------------------------------------------------------
# Uncomment and configure s3.backend.config file
# Then run: terraform init -backend-config=s3.backend.config

terraform {
  backend "s3" {}
}
