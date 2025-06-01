#!/bin/bash

set -e

TFVARS_FILE="terraform.tfvars"
TFVARS_EXAMPLE="terraform.tfvars.example"

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
    local is_pool=$(get_user_input "Is pool? (true/false)" "false" "false")
    
    local vrf_id
    while true; do
        vrf_id=$(get_user_input "VRF ID (optional)" "" "false")
        if [[ -z "$vrf_id" ]] || validate_number "$vrf_id"; then
            break
        fi
    done
    
    local site_id
    while true; do
        site_id=$(get_user_input "Site ID (optional)" "" "false")
        if [[ -z "$site_id" ]] || validate_number "$site_id"; then
            break
        fi
    done
    
    local tenant_id
    while true; do
        tenant_id=$(get_user_input "Tenant ID (optional)" "" "false")
        if [[ -z "$tenant_id" ]] || validate_number "$tenant_id"; then
            break
        fi
    done
    
    local role_id
    while true; do
        role_id=$(get_user_input "Role ID (optional)" "" "false")
        if [[ -z "$role_id" ]] || validate_number "$role_id"; then
            break
        fi
    done
    
    local tags=$(get_user_input "Tags (comma-separated, optional)" "" "false")
    
    add_prefix_to_file "$name" "$prefix" "$description" "$status" "$is_pool" "$vrf_id" "$site_id" "$tenant_id" "$role_id" "$tags"
}

run_terraform_commands() {
    local prefix_name="$1"
    local terraform_cmd="$HOME/bin/terraform"
    
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
    local is_pool="$5"
    local vrf_id="$6"
    local site_id="$7"
    local tenant_id="$8"
    local role_id="$9"
    local tags="${10}"
    
    if grep -q "\"$name\"" "$TFVARS_FILE"; then
        echo "Error: Prefix with name '$name' already exists in $TFVARS_FILE"
        exit 1
    fi
    
    local prefix_block="  \"$name\" = {\n"
    prefix_block+="    prefix      = \"$prefix\"\n"
    
    if [[ -n "$description" ]]; then
        prefix_block+="    description = \"$description\"\n"
    fi
    
    prefix_block+="    status      = \"$status\"\n"
    prefix_block+="    is_pool     = $is_pool\n"
    
    if [[ -n "$vrf_id" ]]; then
        prefix_block+="    vrf_id      = $vrf_id\n"
    fi
    
    if [[ -n "$site_id" ]]; then
        prefix_block+="    site_id     = $site_id\n"
    fi
    
    if [[ -n "$tenant_id" ]]; then
        prefix_block+="    tenant_id   = $tenant_id\n"
    fi
    
    if [[ -n "$role_id" ]]; then
        prefix_block+="    role_id     = $role_id\n"
    fi
    
    if [[ -n "$tags" ]]; then
        IFS=',' read -ra TAG_ARRAY <<< "$tags"
        local tag_list="["
        for i in "${!TAG_ARRAY[@]}"; do
            local tag=$(echo "${TAG_ARRAY[$i]}" | xargs)
            if [[ $i -eq 0 ]]; then
                tag_list+="\"$tag\""
            else
                tag_list+=", \"$tag\""
            fi
        done
        tag_list+="]"
        prefix_block+="    tags        = $tag_list\n"
    fi
    
    prefix_block+="  }\n"
    
    if grep -q "^}" "$TFVARS_FILE"; then
        sed -i "/^}/i\\$prefix_block" "$TFVARS_FILE"
    else
        echo -e "\n$prefix_block" >> "$TFVARS_FILE"
    fi
    
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
    
    create_tfvars_if_not_exists
    
    if [[ "$interactive_mode" == "true" ]]; then
        add_prefix_interactive
    fi
}

main "$@"