#!/bin/bash

set -e

TFVARS_FILE="terraform.tfvars"
TFVARS_EXAMPLE="terraform.tfvars.example"

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Add multiple consecutive /24 IP prefixes to NetBox Terraform configuration.

OPTIONS:
    -h, --help          Show this help message
    -f, --file FILE     Use specific tfvars file (default: terraform.tfvars)
    
EXAMPLES:
    $0                  # Interactive mode
    $0 -f custom.tfvars # Use custom tfvars file

This script will:
1. Ask for a starting IP address (e.g., 10.0.0.0)
2. Validate it's a network address (first IP in a /24)
3. Ask how many consecutive /24 subnets to create
4. Generate and add all subnets to terraform configuration
5. Run terraform to create them in NetBox

EOF
}

validate_network_address() {
    local ip="$1"
    
    # Check basic IP format
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "Error: Invalid IP address format"
        return 1
    fi
    
    # Check each octet is valid (0-255)
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if [[ $octet -lt 0 || $octet -gt 255 ]]; then
            echo "Error: Invalid IP address - octet out of range"
            return 1
        fi
    done
    
    # Check if it's a valid network address for /24 (last octet should be 0)
    if [[ ${OCTETS[3]} -ne 0 ]]; then
        echo "Error: IP address must be a network address for /24 subnet (last octet must be 0)"
        echo "Example: 10.0.0.0, 192.168.1.0, etc."
        return 1
    fi
    
    return 0
}

validate_number() {
    local num="$1"
    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
        echo "Error: Must be a positive number"
        return 1
    fi
    
    if [[ $num -lt 1 || $num -gt 254 ]]; then
        echo "Error: Number of subnets must be between 1 and 254"
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

increment_ip() {
    local ip="$1"
    local increment="$2"
    
    IFS='.' read -ra OCTETS <<< "$ip"
    local third_octet=${OCTETS[2]}
    
    # Increment the third octet
    ((third_octet += increment))
    
    # Check for overflow
    if [[ $third_octet -gt 255 ]]; then
        echo "Error: IP address overflow - cannot create $increment subnets from $ip"
        return 1
    fi
    
    echo "${OCTETS[0]}.${OCTETS[1]}.$third_octet.${OCTETS[3]}"
}

generate_subnet_name() {
    local ip="$1"
    local index="$2"
    local base_name="$3"
    
    # Create name like "subnet_10_0_0" or "network_01", "network_02", etc.
    if [[ -n "$base_name" ]]; then
        printf "%s_%02d" "$base_name" "$((index + 1))"
    else
        echo "subnet_$(echo "$ip" | tr '.' '_')"
    fi
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

add_prefix_to_file() {
    local name="$1"
    local prefix="$2"
    local description="$3"
    local status="$4"
    local is_pool="$5"
    
    if grep -q "\"$name\"" "$TFVARS_FILE"; then
        echo "Warning: Prefix with name '$name' already exists in $TFVARS_FILE, skipping..."
        return 1
    fi
    
    local prefix_block="  \"$name\" = {\n"
    prefix_block+="    prefix      = \"$prefix\"\n"
    prefix_block+="    description = \"$description\"\n"
    prefix_block+="    status      = \"$status\"\n"
    prefix_block+="    is_pool     = $is_pool\n"
    prefix_block+="  }\n"
    
    # Add the prefix before the closing brace
    if grep -q "^}" "$TFVARS_FILE"; then
        sed -i "/^}/i\\$prefix_block" "$TFVARS_FILE"
    else
        echo -e "\n$prefix_block" >> "$TFVARS_FILE"
    fi
    
    return 0
}

run_terraform_commands() {
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
    echo "This will create all the prefixes in NetBox..."
    
    echo "Do you want to apply these changes to NetBox? (y/N)"
    read -r confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        if $terraform_cmd apply -auto-approve; then
            echo "✅ All prefixes successfully created in NetBox!"
        else
            echo "❌ Terraform apply failed"
            return 1
        fi
    else
        echo "⏸️  Terraform apply cancelled. Run 'terraform apply' manually when ready."
    fi
}

add_multiple_prefixes_interactive() {
    echo "=== NetBox Multiple Prefix Generator ==="
    echo "This tool creates consecutive /24 subnets starting from a base network address."
    echo
    
    # Get starting IP address
    local start_ip
    while true; do
        echo "Enter the starting network address (e.g., 10.0.0.0, 192.168.0.0):"
        start_ip=$(get_user_input "Starting IP address" "" "true")
        if validate_network_address "$start_ip"; then
            break
        fi
    done
    
    # Get number of subnets
    local count
    while true; do
        count=$(get_user_input "How many consecutive /24 subnets to create" "12" "true")
        if validate_number "$count"; then
            break
        fi
    done
    
    # Get base name for subnets
    local base_name
    base_name=$(get_user_input "Base name for subnets (optional, e.g., 'network')" "" "false")
    
    # Get common description prefix
    local desc_prefix
    desc_prefix=$(get_user_input "Description prefix" "Subnet" "false")
    
    # Get status and pool settings
    local status
    status=$(get_user_input "Status for all subnets" "active" "false")
    
    local is_pool
    is_pool=$(get_user_input "Are these pool subnets? (true/false)" "false" "false")
    
    echo
    echo "=== Summary ==="
    echo "Starting IP: $start_ip"
    echo "Number of subnets: $count"
    echo "Base name: ${base_name:-'subnet_X_X_X'}"
    echo "Description: $desc_prefix"
    echo "Status: $status"
    echo "Is pool: $is_pool"
    echo
    
    # Generate preview
    echo "Subnets to be created:"
    for ((i=0; i<count; i++)); do
        local current_ip
        current_ip=$(increment_ip "$start_ip" "$i")
        if [[ $? -ne 0 ]]; then
            echo "$current_ip"  # This will be the error message
            exit 1
        fi
        
        local subnet_name
        subnet_name=$(generate_subnet_name "$current_ip" "$i" "$base_name")
        
        echo "  $((i+1)). $subnet_name -> $current_ip/24"
        
        # Show only first 5 and last 2 if more than 7
        if [[ $count -gt 7 && $i -eq 4 ]]; then
            echo "  ... ($(($count - 7)) more) ..."
            i=$((count - 3))
        fi
    done
    
    echo
    read -p "Continue with creating these prefixes? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    echo
    echo "=== Adding Prefixes to Configuration ==="
    
    # Add all prefixes
    local added_count=0
    for ((i=0; i<count; i++)); do
        local current_ip
        current_ip=$(increment_ip "$start_ip" "$i")
        
        local subnet_name
        subnet_name=$(generate_subnet_name "$current_ip" "$i" "$base_name")
        
        local description="$desc_prefix $current_ip/24"
        
        if add_prefix_to_file "$subnet_name" "$current_ip/24" "$description" "$status" "$is_pool"; then
            echo "✓ Added: $subnet_name ($current_ip/24)"
            ((added_count++))
        fi
    done
    
    echo
    echo "✅ Successfully added $added_count out of $count prefixes to $TFVARS_FILE"
    
    if [[ $added_count -gt 0 ]]; then
        run_terraform_commands
    else
        echo "No new prefixes to create."
    fi
}

main() {
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
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    create_tfvars_if_not_exists
    add_multiple_prefixes_interactive
}

main "$@"