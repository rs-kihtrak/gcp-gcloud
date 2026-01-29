#!/bin/bash
###############################################################################
# GCP VM Spec Changer Tool
# Changes GCP VM machine type (CPU/Memory) automatically
#
# Usage:
#   ./vm_spec_changer.sh <gcp-console-url>
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Function to print colored messages
print_info() {
    echo -e "${CYAN}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

# Function to parse GCP URL
parse_gcp_url() {
    local url="$1"
    
    # Remove any URL encoding or backslashes
    url=$(echo "$url" | sed 's/\\//g')
    
    # Extract project from query parameter if present
    local project_from_query=""
    if [[ $url =~ project=([^&\?#]+) ]]; then
        project_from_query="${BASH_REMATCH[1]}"
    fi
    
    # VM URL pattern: zones/ZONE/instances/VM-NAME
    if [[ $url =~ zones/([^/\?#]+)/instances/([^/\?#]+) ]]; then
        ZONE="${BASH_REMATCH[1]}"
        VM_NAME="${BASH_REMATCH[2]}"
        
        # Try to get project from path first, fallback to query parameter
        if [[ $url =~ projects/([^/\?#]+)/zones ]]; then
            PROJECT="${BASH_REMATCH[1]}"
        elif [[ -n "$project_from_query" ]]; then
            PROJECT="$project_from_query"
        else
            print_error "Could not extract project from URL"
            return 1
        fi
        return 0
    fi
    
    print_error "URL does not match VM pattern"
    return 1
}

# Function to get VM current specs
get_vm_specs() {
    local project="$1"
    local zone="$2"
    local vm_name="$3"
    
    gcloud compute instances describe "$vm_name" \
        --project="$project" \
        --zone="$zone" \
        --format="json" 2>/dev/null
}

# Function to display current VM specs
display_current_specs() {
    local vm_info="$1"
    
    local machine_type=$(echo "$vm_info" | jq -r '.machineType' | awk -F'/' '{print $NF}')
    local status=$(echo "$vm_info" | jq -r '.status')
    local cpu_platform=$(echo "$vm_info" | jq -r '.cpuPlatform // "N/A"')
    
    print_header "Current VM Specifications"
    echo -e "${BOLD}VM Name:${NC}        $VM_NAME"
    echo -e "${BOLD}Project:${NC}        $PROJECT"
    echo -e "${BOLD}Zone:${NC}           $ZONE"
    echo -e "${BOLD}Machine Type:${NC}   $machine_type"
    echo -e "${BOLD}Status:${NC}         $status"
    echo -e "${BOLD}CPU Platform:${NC}   $cpu_platform"
    echo ""
}

# Function to list available machine types
list_machine_types() {
    local zone="$1"
    
    print_header "Common Machine Types"
    print_info "To see all available machine types in your zone, run:"
    echo "  gcloud compute machine-types list --zones=$zone"
    echo ""
}

# Function to get VM status
get_vm_status() {
    local project="$1"
    local zone="$2"
    local vm_name="$3"
    
    gcloud compute instances describe "$vm_name" \
        --project="$project" \
        --zone="$zone" \
        --format="value(status)" 2>/dev/null
}

# Function to stop VM
stop_vm() {
    local project="$1"
    local zone="$2"
    local vm_name="$3"
    
    print_info "Stopping VM: $vm_name..."
    
    gcloud compute instances stop "$vm_name" \
        --project="$project" \
        --zone="$zone" \
        --quiet
    
    # Wait for VM to stop
    print_info "Waiting for VM to stop..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(get_vm_status "$project" "$zone" "$vm_name")
        if [ "$status" == "TERMINATED" ]; then
            print_success "VM stopped successfully"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
        echo -n "."
    done
    
    echo ""
    print_error "Timeout waiting for VM to stop"
    return 1
}

# Function to change machine type
change_machine_type() {
    local project="$1"
    local zone="$2"
    local vm_name="$3"
    local new_machine_type="$4"
    
    print_info "Changing machine type to: $new_machine_type..."
    
    gcloud compute instances set-machine-type "$vm_name" \
        --project="$project" \
        --zone="$zone" \
        --machine-type="$new_machine_type" \
        --quiet
    
    print_success "Machine type changed successfully"
}

# Function to start VM
start_vm() {
    local project="$1"
    local zone="$2"
    local vm_name="$3"
    
    print_info "Starting VM: $vm_name..."
    
    gcloud compute instances start "$vm_name" \
        --project="$project" \
        --zone="$zone" \
        --quiet
    
    # Wait for VM to start
    print_info "Waiting for VM to start..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(get_vm_status "$project" "$zone" "$vm_name")
        if [ "$status" == "RUNNING" ]; then
            print_success "VM started successfully"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
        echo -n "."
    done
    
    echo ""
    print_error "Timeout waiting for VM to start"
    return 1
}

# Function to confirm action
confirm_action() {
    local message="$1"
    echo -e "${YELLOW}${BOLD}$message${NC}"
    read -p "Do you want to proceed? (yes/no): " confirmation
    
    case "$confirmation" in
        yes|YES|y|Y)
            return 0
            ;;
        *)
            print_warning "Operation cancelled by user"
            return 1
            ;;
    esac
}

###############################################################################
# Main Script
###############################################################################

print_header "GCP VM Spec Changer"

# Check if URL is provided
if [ $# -eq 0 ]; then
    print_error "No GCP Console URL provided"
    echo ""
    echo "Usage: $0 <gcp-console-url>"
    echo ""
    echo "Example:"
    echo "  $0 'https://console.cloud.google.com/compute/instancesDetail/zones/us-central1-a/instances/my-vm?project=my-project'"
    exit 1
fi

GCP_URL="$1"

# Parse the GCP URL
print_info "Parsing GCP Console URL..."
if ! parse_gcp_url "$GCP_URL"; then
    print_error "Failed to parse GCP URL"
    exit 1
fi

print_success "URL parsed successfully"
print_info "Project: $PROJECT"
print_info "Zone: $ZONE"
print_info "VM: $VM_NAME"
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI is not installed"
    echo "Please install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Get current VM specs
print_info "Fetching current VM specifications..."
VM_INFO=$(get_vm_specs "$PROJECT" "$ZONE" "$VM_NAME")

if [ $? -ne 0 ] || [ -z "$VM_INFO" ]; then
    print_error "Failed to get VM information"
    print_error "Please check your GCP credentials and permissions"
    exit 1
fi

# Display current specs
display_current_specs "$VM_INFO"

# Get current machine type
CURRENT_MACHINE_TYPE=$(echo "$VM_INFO" | jq -r '.machineType' | awk -F'/' '{print $NF}')
CURRENT_STATUS=$(echo "$VM_INFO" | jq -r '.status')

# List available machine types
list_machine_types "$ZONE"

# Prompt for new machine type
echo -e "${BOLD}Enter the new machine type:${NC}"
read -p "> " NEW_MACHINE_TYPE

if [ -z "$NEW_MACHINE_TYPE" ]; then
    print_error "No machine type provided"
    exit 1
fi

# Validate if machine type is different
if [ "$NEW_MACHINE_TYPE" == "$CURRENT_MACHINE_TYPE" ]; then
    print_warning "New machine type is the same as current machine type"
    print_info "No changes needed"
    exit 0
fi

# Display change summary
print_header "Change Summary"
echo -e "${BOLD}VM Name:${NC}              $VM_NAME"
echo -e "${BOLD}Current Machine Type:${NC} $CURRENT_MACHINE_TYPE"
echo -e "${BOLD}New Machine Type:${NC}     $NEW_MACHINE_TYPE"
echo -e "${BOLD}Current Status:${NC}       $CURRENT_STATUS"
echo ""

# Confirm the change
if ! confirm_action "⚠️  This will stop the VM, change the machine type, and restart it."; then
    exit 0
fi

echo ""

# Stop VM if running
if [ "$CURRENT_STATUS" == "RUNNING" ]; then
    if ! stop_vm "$PROJECT" "$ZONE" "$VM_NAME"; then
        print_error "Failed to stop VM"
        exit 1
    fi
    echo ""
elif [ "$CURRENT_STATUS" == "TERMINATED" ]; then
    print_info "VM is already stopped"
else
    print_warning "VM is in status: $CURRENT_STATUS"
    print_info "Attempting to proceed..."
fi

# Change machine type
if ! change_machine_type "$PROJECT" "$ZONE" "$VM_NAME" "$NEW_MACHINE_TYPE"; then
    print_error "Failed to change machine type"
    exit 1
fi

echo ""

# Start VM
if ! start_vm "$PROJECT" "$ZONE" "$VM_NAME"; then
    print_error "Failed to start VM"
    print_warning "VM machine type has been changed, but failed to start"
    print_info "You can start it manually from the GCP Console"
    exit 1
fi

echo ""

# Get and display updated specs
print_info "Fetching updated VM specifications..."
UPDATED_VM_INFO=$(get_vm_specs "$PROJECT" "$ZONE" "$VM_NAME")

if [ $? -eq 0 ] && [ -n "$UPDATED_VM_INFO" ]; then
    display_current_specs "$UPDATED_VM_INFO"
    print_success "VM spec change completed successfully!"
else
    print_warning "Could not fetch updated specs, but operation completed"
fi

print_header "Operation Complete"
print_success "Machine type changed from $CURRENT_MACHINE_TYPE to $NEW_MACHINE_TYPE"
print_success "VM is now running with the new specifications"

exit 0