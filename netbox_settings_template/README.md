# NetBox Settings Template

A data-driven Terraform/OpenTofu template for configuring the initial state of a NetBox instance.

This template allows you to define your infrastructure (Sites, Regions, Prefixes, VLANs, Device Types, etc.) in `terraform.tfvars` and apply them programmatically, ensuring a consistent baseline across environments.

## Features

- **Data-Driven**: No Need to edit Terraform code. Define everything in `terraform.tfvars`.
- **Bulk Creation**: Manage lists of sites, prefixes, and devices easily.
- **Vault Integration**: Securely fetches NetBox API tokens from HashiCorp Vault.
- **Comprehensive Coverage**: Organization, IPAM, DCIM, Virtualization, and Extras.

## Quick Start

### 1. Prerequisites

- OpenTofu or Terraform
- HashiCorp Vault (optional, for token storage)
- NetBox instance

### 2. Configuration

Copy the example variables file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform.tfvars` to define your desired state:

```hcl
netbox_url = "https://netbox.example.com"

sites = {
  "New-York-1" = {
    status = "active"
    region = "US-East"
  }
}
```

### 3. Usage

Use the `apply.sh` wrapper script to handle credentials automatically:

```bash
# Initialize
./apply.sh init

# Plan
./apply.sh plan

# Apply
./apply.sh apply
```

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

## License

MIT
