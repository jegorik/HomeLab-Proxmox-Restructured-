# NetBox Settings Template

A data-driven Terraform/OpenTofu template for configuring the initial state of a NetBox instance.

This template allows you to define your infrastructure (Sites, Regions, Prefixes, VLANs, Device Types, etc.) in `terraform.tfvars` and apply them programmatically, ensuring a consistent baseline across environments.

## Features

- **Data-Driven**: No need to edit Terraform code. Define everything in `terraform.tfvars`.
- **Bulk Creation**: Manage lists of sites, prefixes, and devices easily.
- **Vault Integration**: Securely fetches NetBox API tokens from HashiCorp Vault.
- **Remote State**: S3 backend with state locking.
- **State Encryption**: Vault Transit engine for tfstate encryption.
- **Comprehensive Coverage**: Organization, IPAM, DCIM, Virtualization, and Extras.

## Prerequisites

- OpenTofu >= 1.0 or Terraform >= 1.5
- HashiCorp Vault (running and accessible)
- NetBox instance with API access
- AWS S3 bucket for state storage
- Vault Transit engine enabled with encryption key

### Vault Setup

```bash
# Store NetBox API token
vault kv put secrets/proxmox/netbox_api_token token="your-netbox-api-token"

# Enable Transit engine (if not already)
vault secrets enable transit

# Create encryption key
vault write -f transit/keys/tofu-state-encryption
```

### AWS Credentials

Get dynamic credentials from Vault or configure static credentials:

```bash
# Option 1: Vault dynamic credentials
vault read -format=json aws/proxmox/creds/tofu_state_backup | jq -r '.data'
export AWS_ACCESS_KEY_ID="<access_key>"
export AWS_SECRET_ACCESS_KEY="<secret_key>"

# Option 2: Static credentials via AWS CLI profile
aws configure --profile tofu-backup
```

## Quick Start

### 1. Configure Variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp terraform/s3.backend.config.template terraform/s3.backend.config
vim terraform/terraform.tfvars
vim terraform/s3.backend.config
```

### 2. Authenticate to Vault

```bash
export VAULT_ADDR='https://vault.example.com:8200'
vault login -method=userpass username=YOUR_USER
export VAULT_TOKEN=$(vault print token)
```

### 3. Deploy

```bash
# Interactive menu
./deploy.sh

# Or use CLI commands:
./deploy.sh plan     # Dry-run
./deploy.sh deploy   # Full deployment
./deploy.sh destroy  # Remove resources
./deploy.sh status   # Check status
```

## Configuration Variables

| Variable                      | Description                    | Default                   |
| ----------------------------- | ------------------------------ | ------------------------- |
| `vault_address`               | Vault server URL               | (required)                |
| `vault_skip_tls_verify`       | Skip TLS verification          | `true`                    |
| `vault_kv_mount`              | Vault KV mount path            | `secrets`                 |
| `netbox_api_token_vault_path` | Path to token in Vault         | `netbox_api_token`        |
| `netbox_url`                  | NetBox server URL              | (required)                |
| `aws_region`                  | AWS region for S3 backend      | `eu-central-1`            |
| `transit_key_name`            | Vault Transit key name         | `tofu-state-encryption`   |

## Project Structure

```text
netbox_settings_template/
├── deploy.sh                        # Main deployment script
├── README.md                        # This file
├── scripts/
│   ├── common.sh                    # Logging utilities
│   ├── vault.sh                     # Vault authentication + AWS creds
│   └── terraform.sh                 # Terraform operations
└── terraform/
    ├── backend.tf                   # S3 backend + providers
    ├── encryption.tf                # Vault Transit encryption
    ├── main.tf                      # Resources
    ├── providers.tf                 # Vault + NetBox + AWS providers
    ├── variables.tf                 # Variable definitions
    ├── versions.tf                  # Provider versions
    ├── outputs.tf                   # Outputs
    ├── s3.backend.config            # Backend config (gitignored)
    ├── s3.backend.config.template   # Backend config template
    ├── terraform.tfvars.example     # Example config
    └── terraform.tfvars             # Your config (gitignored)
```

## License

MIT
