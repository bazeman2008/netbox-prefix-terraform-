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