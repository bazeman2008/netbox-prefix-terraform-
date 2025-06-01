# Air-Gapped Deployment Guide

This guide explains how to deploy and use the NetBox Terraform project in an air-gapped (disconnected) environment.

## Overview

An air-gapped environment is one that has no network connectivity to the internet. This requires special preparation to ensure all dependencies and provider binaries are available locally.

## Prerequisites

### System Requirements
- Linux-based system (tested on Ubuntu/Debian)
- Bash shell
- Standard Unix utilities: `grep`, `sed`, `awk`, `head`, `tail`
- `unzip` utility
- `curl` (only needed for initial preparation in connected environment)

### Preparation (Connected Environment)

Before moving to the air-gapped environment, you need to prepare the necessary files:

1. **Check current setup:**
   ```bash
   ./setup-airgapped.sh --check
   ```

2. **Prepare offline bundles:**
   ```bash
   ./setup-airgapped.sh --prepare
   ```

This creates an `offline-bundles/` directory containing:
- Terraform provider binaries
- Installation scripts
- Download scripts for Terraform binary

## Air-Gapped Installation

### Step 1: Transfer Files

Transfer the entire project directory to your air-gapped environment, including:
- All `.sh` scripts
- All `.tf` files
- `terraform.tfvars.example`
- `offline-bundles/` directory (if prepared)

### Step 2: Install Terraform

If Terraform isn't already installed:

```bash
# Extract the Terraform binary (obtained from connected environment)
unzip terraform_*_linux_amd64.zip

# Install system-wide (requires sudo)
sudo mv terraform /usr/local/bin/

# OR install to user directory
mkdir -p $HOME/bin
mv terraform $HOME/bin/
export PATH="$HOME/bin:$PATH"
```

### Step 3: Install Providers

If you have the offline bundle:

```bash
cd /path/to/your/project
/path/to/offline-bundles/install-providers.sh
```

OR manually copy providers if you have them:

```bash
mkdir -p .terraform/providers
cp -r /path/to/providers/* .terraform/providers/
```

### Step 4: Verify Installation

```bash
# Check all dependencies
./setup-airgapped.sh --check

# Verify Terraform can see providers
terraform version
terraform providers
```

## Usage in Air-Gapped Environment

Once setup is complete, the scripts work normally:

### Single Prefix Creation
```bash
./add-prefix.sh
```

### Multiple Prefix Creation
```bash
./add-multiple-prefixes.sh
```

## Troubleshooting

### Common Issues

1. **"terraform command not found"**
   - Ensure Terraform is in your PATH
   - Check `$HOME/bin/terraform` or `/usr/local/bin/terraform`

2. **"Terraform providers not found"**
   - Run the provider installation script
   - Verify `.terraform/providers/` directory exists

3. **"Missing dependencies"**
   - Install required system packages:
     ```bash
     # Ubuntu/Debian
     sudo apt-get update
     sudo apt-get install grep sed gawk coreutils unzip
     ```

4. **Permission errors**
   - Ensure scripts are executable: `chmod +x *.sh`
   - Check file permissions in `.terraform/` directory

### Dependency Check

Run this anytime to verify your setup:
```bash
./setup-airgapped.sh --check
```

## Manual Provider Installation

If automated installation fails, you can manually install providers:

1. **Find your system architecture:**
   ```bash
   uname -m  # Usually x86_64 (amd64) or aarch64 (arm64)
   ```

2. **Create provider directory structure:**
   ```bash
   mkdir -p .terraform/providers/registry.terraform.io/e-breuninger/netbox/3.11.0/linux_amd64/
   ```

3. **Copy provider binary:**
   ```bash
   cp terraform-provider-netbox_v3.11.0 .terraform/providers/registry.terraform.io/e-breuninger/netbox/3.11.0/linux_amd64/
   chmod +x .terraform/providers/registry.terraform.io/e-breuninger/netbox/3.11.0/linux_amd64/terraform-provider-netbox_v3.11.0
   ```

## Security Considerations

- Verify checksums of downloaded binaries before transfer
- Use secure methods to transfer files to air-gapped environment
- Store provider binaries in a secure location
- Regularly update providers when security patches are available

## File Structure

After successful setup, your project should look like:

```
netbox-terraform/
├── add-prefix.sh                 # Main scripts
├── add-multiple-prefixes.sh
├── setup-airgapped.sh           # Setup utility
├── main.tf                      # Terraform configuration
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── README-AIRGAPPED.md          # This file
├── .terraform/                  # Terraform working directory
│   └── providers/
│       └── registry.terraform.io/
│           └── e-breuninger/
│               └── netbox/
│                   └── 3.11.0/
│                       └── linux_amd64/
│                           └── terraform-provider-netbox_v3.11.0
└── offline-bundles/             # Optional: prepared bundles
    ├── providers/
    ├── install-providers.sh
    ├── download-terraform.sh
    └── README.md
```

## Support

For air-gapped deployment issues:

1. First run: `./setup-airgapped.sh --check`
2. Review this guide and troubleshooting section
3. Check file permissions and paths
4. Verify all required system packages are installed

Remember: Once properly configured, the scripts work identically to connected environments!