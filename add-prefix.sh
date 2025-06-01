#!/bin/bash

set -e

TFVARS_FILE="terraform.tfvars"
TFVARS_EXAMPLE="terraform.tfvars.example"

# Dependency checking for air-gapped environments
check_dependencies() {
    local missing_deps=()
    local terraform_cmd=""
    
    # Check for required commands
    for cmd in grep sed awk head tail; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Find Terraform binary
    if command -v terraform >/dev/null 2>&1; then
        terraform_cmd="terraform"
    elif [[ -x "$HOME/bin/terraform" ]]; then
        terraform_cmd="$HOME/bin/terraform"
    elif [[ -x "/usr/local/bin/terraform" ]]; then
        terraform_cmd="/usr/local/bin/terraform"
    else
        missing_deps+=("terraform")
    fi
    
    # Check for provider
    if [[ ! -d ".terraform/providers" ]] && [[ -n "$terraform_cmd" ]]; then
        echo "⚠️  Terraform providers not found. Run 'terraform init' or use setup-airgapped.sh"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "❌ Missing dependencies: ${missing_deps[*]}"
        echo "💡 For air-gapped setup, run: ./setup-airgapped.sh --prepare"
        echo "💡 Then in air-gapped environment: ./setup-airgapped.sh --install"
        exit 1
    fi
    
    echo "✓ All dependencies satisfied"
    
    # Set the terraform command for the rest of the script
    if [[ -n "$terraform_cmd" ]]; then
        export TERRAFORM_CMD="$terraform_cmd"
    fi
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Add IP prefixes to NetBox Terraform configuration.

OPTIONS:
    -h, --help          Show this help message
    -i, --interactive   Interactive mode (default)
    -f, --file FILE     Use specific tfvars file (default: terraform.tfvars)
    
EXAMPLES:
    $0                  # Interactive mode
    $0 -f custom.tfvars # Use custom tfvars file

EOF
}

validate_cidr() {
    local cidr="$1"
    if [[ ! "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid CIDR format. Example: 192.168.1.0/24"
        return 1
    fi
    
    local ip=$(echo "$cidr" | cut -d'/' -f1)
    local prefix=$(echo "$cidr" | cut -d'/' -f2)
    
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if [[ $octet -lt 0 || $octet -gt 255 ]]; then
            echo "Error: Invalid IP address in CIDR"
            return 1
        fi
    done
    
    if [[ $prefix -lt 0 || $prefix -gt 32 ]]; then
        echo "Error: Invalid prefix length. Must be 0-32"
        return 1
    fi
    
    return 0
}

validate_number() {
    local num="$1"
    if [[ -n "$num" && ! "$num" =~ ^[0-9]+$ ]]; then
        echo "Error: Must be a number or empty"
        return 1
    fi
    return 0
}

get_user_input() {
    local prompt="$1"
    local default="$2"
    local required="$3"
    local value
    
    while true; do
        if [[ -n "$default" ]]; then
            read -p "$prompt [$default]: " value
            value="${value:-$default}"
        else
            read -p "$prompt: " value
        fi
        
        if [[ "$required" == "true" && -z "$value" ]]; then
            echo "Error: This field is required"
            continue
        fi
        
        echo "$value"
        break
    done
}

create_tfvars_if_not_exists() {
    if [[ ! -f "$TFVARS_FILE" ]]; then
        if [[ -f "$TFVARS_EXAMPLE" ]]; then
            echo "Creating $TFVARS_FILE from $TFVARS_EXAMPLE..."
            cp "$TFVARS_EXAMPLE" "$TFVARS_FILE"
        else
            echo "Error: Neither $TFVARS_FILE nor $TFVARS_EXAMPLE exists"
            exit 1
        fi
    fi
}

add_prefix_interactive() {
    echo "=== NetBox Prefix Management ==="
    echo
    
    # First ask what prefix they want to add
    local prefix
    while true; do
        echo "What IP prefix would you like to add to NetBox?"
        prefix=$(get_user_input "Enter CIDR prefix (e.g., 192.168.1.0/24, 10.0.0.0/16)" "" "true")
        if validate_cidr "$prefix"; then
            break
        fi
    done
    
    echo
    echo "Adding prefix: $prefix"
    echo "Now let's configure the details..."
    echo
    
    local name
    while true; do
        name=$(get_user_input "Prefix name (unique identifier)" "" "true")
        if [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
            break
        else
            echo "Error: Name must start with letter and contain only letters, numbers, and underscores"
        fi
    done
    
    local description=$(get_user_input "Description" "" "false")
    local status=$(get_user_input "Status" "active" "false")
    
    local tenant_id
    while true; do
        tenant_id=$(get_user_input "Tenant ID (optional)" "" "false")
        if [[ -z "$tenant_id" ]] || validate_number "$tenant_id"; then
            break
        fi
    done
    
    add_prefix_to_file "$name" "$prefix" "$description" "$status" "$tenant_id"
}

run_terraform_commands() {
    local prefix_name="$1"
    local terraform_cmd="${TERRAFORM_CMD:-$HOME/bin/terraform}"
    
    echo
    echo "=== Running Terraform Commands ==="
    echo
    
    # Check if terraform is already initialized
    if [[ ! -d ".terraform" ]]; then
        echo "🔄 Initializing Terraform..."
        if $terraform_cmd init; then
            echo "✓ Terraform initialized successfully"
        else
            echo "❌ Terraform init failed"
            return 1
        fi
        echo
    fi
    
    echo "🔍 Planning Terraform changes..."
    if $terraform_cmd plan; then
        echo "✓ Terraform plan completed"
    else
        echo "❌ Terraform plan failed"
        return 1
    fi
    
    echo
    echo "🚀 Applying Terraform changes..."
    echo "This will create the prefix '$prefix_name' in NetBox..."
    
    echo "Do you want to apply these changes to NetBox? (y/N)"
    read -r confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        if $terraform_cmd apply -auto-approve; then
            echo "✅ Prefix '$prefix_name' successfully created in NetBox!"
        else
            echo "❌ Terraform apply failed"
            return 1
        fi
    else
        echo "⏸️  Terraform apply cancelled. Run 'terraform apply' manually when ready."
    fi
}

add_prefix_to_file() {
    local name="$1"
    local prefix="$2"
    local description="$3"
    local status="$4"
    local tenant_id="$5"
    
    if grep -q "\"$name\"" "$TFVARS_FILE"; then
        echo "Error: Prefix with name '$name' already exists in $TFVARS_FILE"
        exit 1
    fi
    
    # Create a temporary file with the new prefix block
    local temp_file=$(mktemp)
    cat > "$temp_file" << EOF
  "$name" = {
    prefix      = "$prefix"
EOF
    
    if [[ -n "$description" ]]; then
        echo "    description = \"$description\"" >> "$temp_file"
    fi
    
    echo "    status      = \"$status\"" >> "$temp_file"
    
    if [[ -n "$tenant_id" ]]; then
        echo "    tenant_id   = $tenant_id" >> "$temp_file"
    fi
    
    echo "  }" >> "$temp_file"
    echo "  " >> "$temp_file"
    
    # Add the prefix before the closing brace
    if grep -q "^}" "$TFVARS_FILE"; then
        # Create a new file with content inserted before the last closing brace
        local backup_file="${TFVARS_FILE}.backup"
        cp "$TFVARS_FILE" "$backup_file"
        
        # Remove the last closing brace, add our content, then add the closing brace back
        head -n -1 "$TFVARS_FILE" > "${TFVARS_FILE}.tmp"
        cat "$temp_file" >> "${TFVARS_FILE}.tmp"
        echo "}" >> "${TFVARS_FILE}.tmp"
        mv "${TFVARS_FILE}.tmp" "$TFVARS_FILE"
    else
        # Append to the file
        cat "$temp_file" >> "$TFVARS_FILE"
    fi
    
    rm -f "$temp_file"
    echo "✓ Added prefix '$name' to $TFVARS_FILE"
    
    # Run terraform commands
    run_terraform_commands "$name"
}

main() {
    local interactive_mode=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--file)
                TFVARS_FILE="$2"
                shift 2
                ;;
            -i|--interactive)
                interactive_mode=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Check dependencies first
    check_dependencies
    
    create_tfvars_if_not_exists
    
    if [[ "$interactive_mode" == "true" ]]; then
        add_prefix_interactive
    fi
}

main "$@"