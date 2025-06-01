#!/bin/bash

# Air-gapped environment setup script for NetBox Terraform project
# This script prepares the environment with all necessary dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_VERSION="1.5.7"
NETBOX_PROVIDER_VERSION="3.11.0"

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup script for air-gapped NetBox Terraform environment.

OPTIONS:
    -h, --help          Show this help message
    -c, --check         Check dependencies only (don't install)
    -i, --install       Install missing dependencies
    -p, --prepare       Prepare offline bundles for air-gapped deployment
    
EXAMPLES:
    $0 --check         # Check what dependencies are missing
    $0 --install       # Install missing dependencies
    $0 --prepare       # Prepare offline bundles

EOF
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_command() {
    local cmd="$1"
    local desc="$2"
    local install_hint="$3"
    local optional="$4"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        log "✓ $desc found: $(command -v "$cmd")"
        return 0
    else
        if [[ "$optional" == "true" ]]; then
            log "⚠️  $desc not found (optional)"
        else
            log "❌ $desc not found"
        fi
        if [[ -n "$install_hint" ]]; then
            log "   Install with: $install_hint"
        fi
        return 1
    fi
}

check_terraform() {
    if command -v terraform >/dev/null 2>&1; then
        log "✓ Terraform found: $(command -v terraform)"
        return 0
    else
        log "❌ Terraform not found"
        log "   Expected location: $HOME/bin/terraform"
        return 1
    fi
}

check_dependencies() {
    log "=== Checking Dependencies ==="
    local missing=0
    local warn_only=0
    
    # Check essential commands
    check_command "bash" "Bash shell" || ((missing++))
    check_command "curl" "curl" "apt-get install curl" || ((missing++))
    check_command "grep" "grep" || ((missing++))
    check_command "sed" "sed" || ((missing++))
    check_command "awk" "awk" || ((missing++))
    
    # Check optional commands
    check_command "unzip" "unzip" "apt-get install unzip" "true" || ((warn_only++))
    
    # Check Terraform
    check_terraform || ((missing++))
    
    # Check if provider is available
    if [[ -f ".terraform/providers/registry.terraform.io/e-breuninger/netbox/$NETBOX_PROVIDER_VERSION/linux_amd64/terraform-provider-netbox_v$NETBOX_PROVIDER_VERSION" ]]; then
        log "✓ NetBox provider found (version: $NETBOX_PROVIDER_VERSION)"
    else
        log "❌ NetBox provider not found"
        ((missing++))
    fi
    
    log ""
    if [[ $warn_only -gt 0 ]]; then
        log "⚠️  $warn_only optional dependencies missing (unzip - needed for Terraform installation)"
    fi
    
    if [[ $missing -eq 0 ]]; then
        log "✅ Essential dependencies satisfied"
        return 0
    else
        log "❌ $missing critical dependencies missing"
        return 1
    fi
}

create_terraform_bundle() {
    log "=== Creating Terraform Provider Bundle ==="
    
    local bundle_dir="$SCRIPT_DIR/offline-bundles"
    mkdir -p "$bundle_dir/providers"
    mkdir -p "$bundle_dir/terraform"
    
    # Copy current provider if it exists
    if [[ -d ".terraform/providers" ]]; then
        log "📦 Copying current providers..."
        cp -r .terraform/providers/* "$bundle_dir/providers/"
    fi
    
    # Create provider bundle script
    cat > "$bundle_dir/install-providers.sh" << 'EOF'
#!/bin/bash
# Provider installation script for air-gapped environments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=".terraform/providers"

echo "Installing Terraform providers for air-gapped environment..."

if [[ ! -d "$SCRIPT_DIR/providers" ]]; then
    echo "❌ Provider bundle not found in $SCRIPT_DIR/providers"
    exit 1
fi

# Create target directory
mkdir -p "$TARGET_DIR"

# Copy providers
echo "📦 Installing providers..."
cp -r "$SCRIPT_DIR/providers/"* "$TARGET_DIR/"

echo "✅ Providers installed successfully"
echo "Provider location: $(pwd)/$TARGET_DIR"

# List installed providers
echo ""
echo "Installed providers:"
find "$TARGET_DIR" -name "terraform-provider-*" -type f | while read provider; do
    echo "  - $(basename "$(dirname "$(dirname "$(dirname "$provider")")")")/$(basename "$(dirname "$(dirname "$provider")")")"
done
EOF
    
    chmod +x "$bundle_dir/install-providers.sh"
    
    # Create Terraform download script
    cat > "$bundle_dir/download-terraform.sh" << EOF
#!/bin/bash
# Download Terraform binary for air-gapped deployment

TERRAFORM_VERSION="$TERRAFORM_VERSION"
ARCH="\$(uname -m)"
OS="\$(uname -s | tr '[:upper:]' '[:lower:]')"

case "\$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="arm" ;;
esac

TERRAFORM_URL="https://releases.hashicorp.com/terraform/\${TERRAFORM_VERSION}/terraform_\${TERRAFORM_VERSION}_\${OS}_\${ARCH}.zip"

echo "Downloading Terraform \$TERRAFORM_VERSION for \$OS/\$ARCH..."
echo "URL: \$TERRAFORM_URL"

curl -L -o "terraform_\${TERRAFORM_VERSION}_\${OS}_\${ARCH}.zip" "\$TERRAFORM_URL"

if [[ \$? -eq 0 ]]; then
    echo "✅ Download completed: terraform_\${TERRAFORM_VERSION}_\${OS}_\${ARCH}.zip"
    echo ""
    echo "To install:"
    echo "  unzip terraform_\${TERRAFORM_VERSION}_\${OS}_\${ARCH}.zip"
    echo "  sudo mv terraform /usr/local/bin/  # or move to \$HOME/bin/"
else
    echo "❌ Download failed"
    exit 1
fi
EOF
    
    chmod +x "$bundle_dir/download-terraform.sh"
    
    # Create installation README
    cat > "$bundle_dir/README.md" << EOF
# Air-Gapped Installation Bundle

This bundle contains everything needed to run the NetBox Terraform project in an air-gapped environment.

## Contents

- \`providers/\` - Terraform provider binaries
- \`install-providers.sh\` - Script to install providers
- \`download-terraform.sh\` - Script to download Terraform (run in connected environment)

## Installation Steps

### 1. In Connected Environment (before going air-gapped)

Run the download script to get Terraform binary:
\`\`\`bash
./download-terraform.sh
\`\`\`

### 2. In Air-Gapped Environment

1. Extract this bundle to your target system
2. Install Terraform binary:
   \`\`\`bash
   unzip terraform_*.zip
   sudo mv terraform /usr/local/bin/
   # or 
   mkdir -p \$HOME/bin && mv terraform \$HOME/bin/
   \`\`\`

3. Navigate to your NetBox Terraform project directory
4. Install providers:
   \`\`\`bash
   /path/to/bundle/install-providers.sh
   \`\`\`

5. Verify installation:
   \`\`\`bash
   terraform version
   terraform providers
   \`\`\`

## Dependencies

The following system packages must be installed:
- bash
- curl (for initial download only)
- unzip
- grep, sed, awk (standard Unix tools)

EOF
    
    log "📁 Bundle created in: $bundle_dir"
    log "✅ Offline bundle preparation complete"
}

install_dependencies() {
    log "=== Installing Dependencies ==="
    
    # Check if running as root for system-wide installation
    if [[ $EUID -eq 0 ]]; then
        log "Running as root - will install system-wide"
        PKG_INSTALL="apt-get install -y"
    else
        log "Running as user - will install to \$HOME/bin"
        mkdir -p "$HOME/bin"
    fi
    
    # Install Terraform if missing
    if ! command -v terraform >/dev/null 2>&1; then
        log "📥 Installing Terraform..."
        
        if [[ $EUID -eq 0 ]]; then
            # System-wide installation
            wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
            apt update && apt install terraform
        else
            # User installation
            ARCH="$(uname -m)"
            OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
            case "$ARCH" in
                x86_64) ARCH="amd64" ;;
                aarch64) ARCH="arm64" ;;
                armv7l) ARCH="arm" ;;
            esac
            
            TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip"
            
            curl -L -o "/tmp/terraform.zip" "$TERRAFORM_URL"
            unzip "/tmp/terraform.zip" -d "/tmp/"
            mv "/tmp/terraform" "$HOME/bin/"
            rm "/tmp/terraform.zip"
            
            log "✅ Terraform installed to $HOME/bin/terraform"
        fi
    fi
    
    log "✅ Dependencies installation complete"
}

prepare_airgapped_scripts() {
    log "=== Preparing Air-Gapped Script Versions ==="
    
    # Backup original scripts
    cp add-prefix.sh add-prefix.sh.original
    cp add-multiple-prefixes.sh add-multiple-prefixes.sh.original
    
    # The scripts are already designed to work offline once dependencies are met
    # We just need to ensure they use local Terraform installation
    
    log "✅ Scripts prepared for air-gapped use"
}

main() {
    local action=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--check)
                action="check"
                shift
                ;;
            -i|--install)
                action="install"
                shift
                ;;
            -p|--prepare)
                action="prepare"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$action" ]]; then
        show_help
        exit 1
    fi
    
    case "$action" in
        check)
            check_dependencies
            ;;
        install)
            install_dependencies
            check_dependencies
            ;;
        prepare)
            check_dependencies
            create_terraform_bundle
            prepare_airgapped_scripts
            ;;
    esac
}

main "$@"