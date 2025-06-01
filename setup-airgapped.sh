#!/bin/bash

# Air-gapped environment setup script for NetBox Terraform project
# This script sets up the environment using ONLY offline bundles - NO INTERNET ACCESS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_BUNDLES="$SCRIPT_DIR/offline-bundles"
TERRAFORM_VERSION="1.5.7"
NETBOX_PROVIDER_VERSION="3.11.0"

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Air-gapped setup script for NetBox Terraform environment.
This script works OFFLINE ONLY using files from offline-bundles/ directory.

OPTIONS:
    -h, --help          Show this help message
    -c, --check         Check if environment is properly configured
    -i, --install       Install providers and setup from offline bundles
    
EXAMPLES:
    $0 --check         # Check if everything is configured
    $0 --install       # Install providers from offline bundles

REQUIREMENTS:
- offline-bundles/ directory must exist with provider files
- No internet access required or used
- All dependencies must be pre-installed on the system

EOF
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_command() {
    local cmd="$1"
    local desc="$2"
    local required="$3"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        log "✓ $desc found: $(command -v "$cmd")"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            log "❌ $desc not found (REQUIRED for air-gapped environment)"
        else
            log "⚠️  $desc not found (optional)"
        fi
        return 1
    fi
}

check_terraform() {
    if command -v terraform >/dev/null 2>&1; then
        log "✓ Terraform found: $(command -v terraform)"
        local version=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 2>/dev/null || terraform version | head -n1 | grep -o 'v[0-9.]*' | tr -d 'v')
        log "  Version: $version"
        return 0
    else
        log "❌ Terraform not found"
        log "   Terraform must be pre-installed in air-gapped environment"
        return 1
    fi
}

check_offline_bundles() {
    log "=== Checking Offline Bundles ==="
    local missing=0
    
    # Check if offline bundles directory exists
    if [[ ! -d "$OFFLINE_BUNDLES" ]]; then
        log "❌ Offline bundles directory not found: $OFFLINE_BUNDLES"
        ((missing++))
        return 1
    fi
    
    log "✓ Offline bundles directory found"
    
    # Check if provider files exist
    local provider_dir="$OFFLINE_BUNDLES/providers/registry.terraform.io/e-breuninger/netbox/$NETBOX_PROVIDER_VERSION/linux_amd64"
    local provider_binary="$provider_dir/terraform-provider-netbox_v$NETBOX_PROVIDER_VERSION"
    
    if [[ -f "$provider_binary" ]]; then
        log "✓ NetBox provider binary found: $provider_binary"
    else
        log "❌ NetBox provider binary not found: $provider_binary"
        ((missing++))
    fi
    
    # Check install script
    if [[ -f "$OFFLINE_BUNDLES/install-providers.sh" ]]; then
        log "✓ Provider install script found"
    else
        log "❌ Provider install script not found: $OFFLINE_BUNDLES/install-providers.sh"
        ((missing++))
    fi
    
    return $missing
}

check_dependencies() {
    log "=== Checking Air-Gapped Environment ==="
    local missing=0
    
    # Check essential commands (must be pre-installed)
    check_command "bash" "Bash shell" "true" || ((missing++))
    check_command "grep" "grep" "true" || ((missing++))
    check_command "sed" "sed" "true" || ((missing++))
    check_command "awk" "awk" "true" || ((missing++))
    check_command "cp" "cp" "true" || ((missing++))
    check_command "mkdir" "mkdir" "true" || ((missing++))
    check_command "find" "find" "true" || ((missing++))
    
    # Check Terraform (must be pre-installed)
    check_terraform || ((missing++))
    
    # Check offline bundles
    check_offline_bundles || ((missing++))
    
    # Check if providers are already installed
    local installed_provider=".terraform/providers/registry.terraform.io/e-breuninger/netbox/$NETBOX_PROVIDER_VERSION/linux_amd64/terraform-provider-netbox_v$NETBOX_PROVIDER_VERSION"
    if [[ -f "$installed_provider" ]]; then
        log "✓ NetBox provider already installed"
    else
        log "⚠️  NetBox provider not yet installed (run --install to fix)"
    fi
    
    log ""
    if [[ $missing -eq 0 ]]; then
        log "✅ Air-gapped environment ready"
        return 0
    else
        log "❌ $missing critical components missing"
        log "   This is an air-gapped environment - all dependencies must be pre-installed"
        return 1
    fi
}

install_providers_offline() {
    log "=== Installing Providers from Offline Bundles ==="
    
    # Check if offline bundles exist
    if [[ ! -d "$OFFLINE_BUNDLES" ]]; then
        log "❌ Offline bundles directory not found: $OFFLINE_BUNDLES"
        return 1
    fi
    
    # Direct provider installation without external script
    local provider_source="$OFFLINE_BUNDLES/providers"
    local provider_dest="$SCRIPT_DIR/.terraform/providers"
    
    if [[ ! -d "$provider_source" ]]; then
        log "❌ Provider bundle not found in $provider_source"
        return 1
    fi
    
    # Create target directory structure
    log "📦 Installing providers to $provider_dest..."
    mkdir -p "$provider_dest"
    
    # Copy all provider files maintaining directory structure
    if cp -r "$provider_source/"* "$provider_dest/"; then
        log "✅ Providers copied successfully"
    else
        log "❌ Failed to copy providers"
        return 1
    fi
    
    # Make all provider binaries executable
    find "$provider_dest" -name "terraform-provider-*" -type f -exec chmod +x {} \;
    log "✓ Provider binaries made executable"
    
    # Verify installation
    local installed_provider=".terraform/providers/registry.terraform.io/e-breuninger/netbox/$NETBOX_PROVIDER_VERSION/linux_amd64/terraform-provider-netbox_v$NETBOX_PROVIDER_VERSION"
    if [[ -f "$installed_provider" ]]; then
        log "✅ NetBox provider verified: $installed_provider"
        # Make sure provider is executable
        chmod +x "$installed_provider"
    else
        log "❌ Provider verification failed: $installed_provider"
        return 1
    fi
    
    return 0
}

setup_terraform_workspace() {
    log "=== Setting up Terraform Workspace ==="
    
    # Create plugin cache directory to force offline mode
    local plugin_dir="$SCRIPT_DIR/.terraform/providers"
    
    # Setup Terraform CLI configuration for offline mode
    export TF_CLI_CONFIG_FILE="$SCRIPT_DIR/.terraformrc"
    log "✓ Terraform CLI configured for offline mode"
    
    # Initialize Terraform if not already done
    if [[ ! -d ".terraform" ]]; then
        log "🔄 Initializing Terraform workspace (offline mode)..."
        # Use -plugin-dir to prevent any network access
        if terraform init -plugin-dir="$plugin_dir"; then
            log "✅ Terraform workspace initialized (offline)"
        else
            log "❌ Terraform initialization failed"
            return 1
        fi
    else
        log "✓ Terraform workspace already exists"
    fi
    
    # Verify provider is working
    log "🔍 Verifying Terraform configuration..."
    if terraform validate; then
        log "✅ Terraform configuration is valid"
    else
        log "❌ Terraform configuration validation failed"
        return 1
    fi
    
    return 0
}

install_offline() {
    log "=== Starting Air-Gapped Installation ==="
    
    # Install providers
    if ! install_providers_offline; then
        log "❌ Provider installation failed"
        return 1
    fi
    
    # Setup Terraform workspace
    if ! setup_terraform_workspace; then
        log "❌ Terraform workspace setup failed"
        return 1
    fi
    
    log "✅ Air-gapped installation completed successfully"
    log ""
    log "You can now use the NetBox Terraform scripts:"
    log "  ./add-prefix.sh"
    log "  ./add-multiple-prefixes.sh"
    
    return 0
}

# Main script logic
main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--check)
                check_dependencies
                exit $?
                ;;
            -i|--install)
                if check_dependencies; then
                    log "Environment checks passed, proceeding with installation..."
                else
                    log "Environment checks failed, cannot proceed with installation"
                    exit 1
                fi
                install_offline
                exit $?
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Default action if no arguments
    show_help
    exit 1
}

main "$@"