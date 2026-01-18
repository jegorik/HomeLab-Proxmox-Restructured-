# NetBox Settings Template

A data-driven Terraform/OpenTofu template for configuring the initial state of a NetBox instance.

This template allows you to define your infrastructure (Sites, Regions, Prefixes, VLANs, Device Types, etc.) in `terraform.tfvars` and apply them programmatically, ensuring a consistent baseline across environments.

## Features

- **Data-Driven**: No need to edit Terraform code. Define everything in `terraform.tfvars`.
- **Bulk Creation**: Manage lists of sites, prefixes, and devices easily.
- **Vault Integration**: Securely fetches NetBox API tokens from HashiCorp Vault.
- **Comprehensive Coverage**: Organization, IPAM, DCIM, Virtualization, and Extras.

## Prerequisites

- OpenTofu >= 1.0 or Terraform >= 1.5
- HashiCorp Vault (running and accessible)
- NetBox instance with API access

### Vault Secret Required

Store your NetBox API token in Vault:

```bash
vault kv put secrets/proxmox/netbox_api_token token="your-netbox-api-token"
```

## Quick Start

### 1. Configure Variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars
```

Edit with your actual Vault address, NetBox URL, and desired configuration.

### 2. Authenticate to Vault

```bash
export VAULT_ADDR='https://vault.example.com:8200'
vault login -method=userpass username=YOUR_USER
export VAULT_TOKEN=$(vault print token)
```

### 3. Run Terraform

```bash
# Initialize
./apply.sh init

# Plan
./apply.sh plan

# Apply
./apply.sh apply
```

## Configuration Variables

| Variable                      | Description                    | Default                    |
| ----------------------------- | ------------------------------ | -------------------------- |
| `vault_address`               | Vault server URL               | (required)                 |
| `vault_skip_tls_verify`       | Skip TLS verification          | `true`                     |
| `vault_kv_mount`              | Vault KV mount path            | `secrets`                  |
| `netbox_api_token_vault_path` | Path to token in Vault         | `proxmox/netbox_api_token` |
| `netbox_url`                  | NetBox server URL              | (required)                 |
| `netbox_insecure`             | Skip TLS for NetBox            | `true`                     |

## Managed Resources

### Organization

- Regions, Site Groups, Sites
- Tenants, Tenant Groups

### IPAM

- RIRs, Aggregates
- VRFs, Prefixes
- VLAN Groups, VLANs

### DCIM

- Manufacturers
- Device Types, Device Roles
- Platforms

### Virtualization

- Cluster Types, Cluster Groups, Clusters

### Extras

- Tags

## Project Structure

```text
netbox_settings_template/
├── apply.sh                      # Wrapper script
├── README.md                     # This file
├── scripts/
│   └── common.sh                 # Logging utilities
└── terraform/
    ├── main.tf                   # Resources
    ├── providers.tf              # Vault + NetBox providers
    ├── variables.tf              # Variable definitions
    ├── versions.tf               # Provider versions
    ├── outputs.tf                # Outputs
    ├── terraform.tfvars.example  # Example config
    └── terraform.tfvars          # Your config (gitignored)
```

## License

MIT
