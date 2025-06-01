# NetBox Terraform - Prefix Management

This Terraform project manages IP prefixes in NetBox using the NetBox Terraform provider.

## Prerequisites

- Terraform >= 1.0
- NetBox instance with API access
- Valid NetBox API token

## Usage

1. Create the required configuration files:
   ```bash
   # Create NetBox host file
   echo "https://your-netbox-instance.com" > netbox.host
   
   # Create NetBox API key file
   echo "your-api-token-here" > netbox.key
   
   # Copy example configuration
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Configure your prefixes in `terraform.tfvars`:
   - The NetBox URL and API token are automatically loaded from `netbox.host` and `netbox.key`
   - Add your prefixes to the `prefixes` map

3. Initialize and apply Terraform:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Configuration

### Variables

- `netbox_url`: URL of your NetBox instance (loaded from `netbox.host` file)
- `netbox_api_token`: API token for NetBox authentication (loaded from `netbox.key` file)
- `prefixes`: Map of prefix configurations

### Security

Sensitive files are excluded from version control:
- `netbox.key` - Contains your NetBox API token
- `netbox.host` - Contains your NetBox server URL
- `terraform.tfvars` - Contains your configuration
- `*.tfstate` - Contains Terraform state files

These files are automatically ignored by Git via `.gitignore`.

### Prefix Configuration

Each prefix supports:
- `prefix`: CIDR notation (required)
- `description`: Human-readable description
- `status`: Prefix status (default: "active")
- `is_pool`: Whether prefix is a pool (default: false)
- `vrf_id`: VRF ID (optional)
- `site_id`: Site ID (optional)
- `tenant_id`: Tenant ID (optional)
- `role_id`: Role ID (optional)
- `tags`: List of tags (optional)

## Outputs

- `prefix_ids`: Map of prefix names to NetBox IDs
- `prefix_details`: Complete details of all created prefixes