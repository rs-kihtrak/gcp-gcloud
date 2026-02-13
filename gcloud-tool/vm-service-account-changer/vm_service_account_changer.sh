#!/bin/bash
################################################################################
# GCP VM Service Account Manager
# 
# Usage:
#   ./gcp_vm_service_account_manager.sh "VM_URL"
#
# Example:
#   ./gcp_vm_service_account_manager.sh "https://console.cloud.google.com/compute/instancesDetail/zones/asia-south1-a/instances/kafka-connect-1?project=prod"
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "\n${CYAN}${BOLD}▶${NC} ${BOLD}$1${NC}"; }

print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║    GCP VM Service Account Manager                    ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Unescape URL (handles \? and other escaped characters from Mac terminal)
unescape_url() {
    local url="$1"
    # Remove backslashes that Mac terminal adds
    url=$(echo "$url" | sed 's/\\?/?/g' | sed 's/\\&/\&/g' | sed 's/\\=/=/g')
    echo "$url"
}

parse_vm_url() {
    local url="$1"
    
    # Unescape the URL first
    url=$(unescape_url "$url")
    
    # Extract zone and instance from URL
    # Pattern: zones/ZONE/instances/INSTANCE
    if [[ "$url" =~ zones/([^/]+)/instances/([^?&]+) ]]; then
        ZONE="${BASH_REMATCH[1]}"
        INSTANCE="${BASH_REMATCH[2]}"
    else
        log_error "Could not parse zone and instance from URL"
        echo "URL: $url"
        return 1
    fi
    
    # Extract project
    # Pattern: ?project=PROJECT or &project=PROJECT
    if [[ "$url" =~ project=([^&]+) ]]; then
        PROJECT="${BASH_REMATCH[1]}"
    else
        log_error "Could not parse project from URL"
        echo "URL: $url"
        return 1
    fi
    
    return 0
}

get_vm_details() {
    local project="$1"
    local zone="$2"
    local instance="$3"
    
    log_info "Fetching VM details from GCP..."
    
    if ! VM_DETAILS=$(gcloud compute instances describe "$instance" \
        --project="$project" \
        --zone="$zone" \
        --format="json" 2>&1); then
        log_error "Failed to fetch VM details"
        echo "$VM_DETAILS" >&2
        return 1
    fi
    
    echo "$VM_DETAILS"
    return 0
}

get_current_sa() {
    local project="$1"
    local zone="$2"
    local instance="$3"
    
    local sa
    sa=$(gcloud compute instances describe "$instance" \
        --project="$project" \
        --zone="$zone" \
        --format="value(serviceAccounts[0].email)" 2>/dev/null || echo "")
    
    if [[ -z "$sa" ]] || [[ "$sa" == "None" ]]; then
        echo "No service account"
    else
        echo "$sa"
    fi
}

get_vm_status() {
    local project="$1"
    local zone="$2"
    local instance="$3"
    
    gcloud compute instances describe "$instance" \
        --project="$project" \
        --zone="$zone" \
        --format="value(status)" 2>/dev/null || echo "UNKNOWN"
}

get_vm_machine_type() {
    local project="$1"
    local zone="$2"
    local instance="$3"
    
    gcloud compute instances describe "$instance" \
        --project="$project" \
        --zone="$zone" \
        --format="value(machineType)" 2>/dev/null | awk -F'/' '{print $NF}'
}

get_vm_internal_ip() {
    local project="$1"
    local zone="$2"
    local instance="$3"
    
    gcloud compute instances describe "$instance" \
        --project="$project" \
        --zone="$zone" \
        --format="value(networkInterfaces[0].networkIP)" 2>/dev/null || echo "N/A"
}

check_sa_exists() {
    local project="$1"
    local sa_email="$2"
    
    if gcloud iam service-accounts describe "$sa_email" \
        --project="$project" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

create_service_account() {
    local project="$1"
    local sa_email="$2"
    
    local sa_name="${sa_email%%@*}"
    
    log_info "Creating service account: $sa_name"
    
    if gcloud iam service-accounts create "$sa_name" \
        --project="$project" \
        --display-name="$sa_name" \
        --description="Service account for VM (auto-created)" 2>&1; then
        log_success "Service account created: $sa_email"
        return 0
    else
        log_error "Failed to create service account"
        return 1
    fi
}

stop_vm() {
    local project="$1"
    local zone="$2"
    local instance="$3"
    
    log_info "Stopping VM: $instance"
    
    if gcloud compute instances stop "$instance" \
        --project="$project" \
        --zone="$zone" \
        --quiet 2>&1; then
        
        log_info "Waiting for VM to stop..."
        local max_wait=60
        local elapsed=0
        while [[ $elapsed -lt $max_wait ]]; do
            local status
            status=$(get_vm_status "$project" "$zone" "$instance")
            if [[ "$status" == "TERMINATED" ]]; then
                log_success "VM stopped"
                return 0
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done
        
        log_warning "VM did not stop within ${max_wait}s, but continuing..."
        return 0
    else
        log_error "Failed to stop VM"
        return 1
    fi
}

set_service_account() {
    local project="$1"
    local zone="$2"
    local instance="$3"
    local sa_email="$4"
    
    log_info "Setting service account: $sa_email"
    
    if gcloud compute instances set-service-account "$instance" \
        --project="$project" \
        --zone="$zone" \
        --service-account="$sa_email" \
        --scopes="cloud-platform" 2>&1; then
        log_success "Service account updated"
        return 0
    else
        log_error "Failed to set service account"
        return 1
    fi
}

start_vm() {
    local project="$1"
    local zone="$2"
    local instance="$3"
    
    log_info "Starting VM: $instance"
    
    if gcloud compute instances start "$instance" \
        --project="$project" \
        --zone="$zone" \
        --quiet 2>&1; then
        
        log_info "Waiting for VM to start..."
        local max_wait=60
        local elapsed=0
        while [[ $elapsed -lt $max_wait ]]; do
            local status
            status=$(get_vm_status "$project" "$zone" "$instance")
            if [[ "$status" == "RUNNING" ]]; then
                log_success "VM started"
                return 0
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done
        
        log_warning "VM did not start within ${max_wait}s, check console"
        return 0
    else
        log_error "Failed to start VM"
        return 1
    fi
}

main() {
    local vm_url="$1"
    
    print_banner
    
    log_step "Step 1: Parsing VM URL"
    
    # Show original URL for debugging
    log_info "Original URL: $vm_url"
    
    if ! parse_vm_url "$vm_url"; then
        log_error "Invalid VM URL format"
        echo
        echo "Expected format:"
        echo "  https://console.cloud.google.com/compute/instancesDetail/zones/ZONE/instances/INSTANCE?project=PROJECT"
        echo
        echo "Note: You can copy-paste directly from browser (escaped characters are handled)"
        exit 1
    fi
    
    echo
    log_info "Project:  ${YELLOW}$PROJECT${NC}"
    log_info "Zone:     ${YELLOW}$ZONE${NC}"
    log_info "Instance: ${YELLOW}$INSTANCE${NC}"
    
    log_step "Step 2: Fetching VM Details"
    
    if ! get_vm_details "$PROJECT" "$ZONE" "$INSTANCE" > /dev/null; then
        log_error "VM not found or no permission to access it"
        exit 1
    fi
    
    local current_sa
    current_sa=$(get_current_sa "$PROJECT" "$ZONE" "$INSTANCE")
    
    local vm_status
    vm_status=$(get_vm_status "$PROJECT" "$ZONE" "$INSTANCE")
    
    local machine_type
    machine_type=$(get_vm_machine_type "$PROJECT" "$ZONE" "$INSTANCE")
    
    local internal_ip
    internal_ip=$(get_vm_internal_ip "$PROJECT" "$ZONE" "$INSTANCE")
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BOLD}VM Details${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  Instance:             ${CYAN}$INSTANCE${NC}"
    echo -e "  Status:               ${MAGENTA}$vm_status${NC}"
    echo -e "  Machine Type:         $machine_type"
    echo -e "  Internal IP:          $internal_ip"
    echo -e "  Current SA:           ${YELLOW}$current_sa${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    log_step "Step 3: New Service Account"
    echo
    echo "Enter the service account email (format: NAME@PROJECT.iam.gserviceaccount.com)"
    read -p "$(echo -e "${CYAN}Service account email:${NC} ")" new_sa
    
    if [[ -z "$new_sa" ]]; then
        log_error "Service account email cannot be empty"
        exit 1
    fi
    
    # Validate email format (simpler check without problematic regex)
    if [[ "$new_sa" != *"@"*".iam.gserviceaccount.com" ]]; then
        log_warning "Service account email should end with .iam.gserviceaccount.com"
        read -p "$(echo -e "${YELLOW}Continue anyway? [y/N]:${NC} ")" -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled"
            exit 0
        fi
    fi
    
    log_step "Step 4: Checking Service Account"
    echo
    log_info "Checking if service account exists..."
    
    if check_sa_exists "$PROJECT" "$new_sa"; then
        log_success "Service account exists: $new_sa"
    else
        log_warning "Service account does NOT exist: $new_sa"
        echo
        read -p "$(echo -e "${YELLOW}Create this service account? [y/N]:${NC} ")" -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo
            if ! create_service_account "$PROJECT" "$new_sa"; then
                log_error "Cannot proceed without service account"
                exit 1
            fi
        else
            log_error "Cannot proceed without service account"
            exit 1
        fi
    fi
    
    log_step "Step 5: Confirm Changes"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BOLD}Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  VM Instance:          ${CYAN}$INSTANCE${NC}"
    echo -e "  Current SA:           ${YELLOW}$current_sa${NC}"
    echo -e "  New SA:               ${GREEN}$new_sa${NC}"
    echo -e "  Scopes:               ${BLUE}cloud-platform${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -e "${YELLOW}${BOLD}WARNING:${NC} This will STOP the VM, change the service account, and START it again."
    echo
    read -p "$(echo -e "${YELLOW}Proceed with VM shutdown and service account change? [y/N]:${NC} ")" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
    
    log_step "Step 6: Stopping VM"
    echo
    
    if ! stop_vm "$PROJECT" "$ZONE" "$INSTANCE"; then
        log_error "Failed to stop VM"
        exit 1
    fi
    
    log_step "Step 7: Changing Service Account"
    echo
    
    if ! set_service_account "$PROJECT" "$ZONE" "$INSTANCE" "$new_sa"; then
        log_error "Failed to change service account"
        log_warning "VM is STOPPED. You may need to start it manually."
        exit 1
    fi
    
    log_step "Step 8: Starting VM"
    echo
    
    if ! start_vm "$PROJECT" "$ZONE" "$INSTANCE"; then
        log_error "Failed to start VM"
        log_warning "Service account was changed, but VM did not start. Start it manually."
        exit 1
    fi
    
    log_step "Step 9: Verifying Changes"
    echo
    
    log_info "Verifying service account change..."
    sleep 2
    
    local final_sa
    final_sa=$(get_current_sa "$PROJECT" "$ZONE" "$INSTANCE")
    
    if [[ "$final_sa" == "$new_sa" ]]; then
        log_success "Service account successfully changed!"
        echo
        echo -e "${GREEN}${BOLD}✓ All done!${NC}"
        echo
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "  Instance:             ${CYAN}$INSTANCE${NC}"
        echo -e "  New Service Account:  ${GREEN}$final_sa${NC}"
        echo -e "  Status:               ${MAGENTA}RUNNING${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
    else
        log_error "Verification failed!"
        echo "  Expected: $new_sa"
        echo "  Got:      $final_sa"
        exit 1
    fi
}

check_prerequisites() {
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        echo "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud"
        echo "Run: gcloud auth login"
        exit 1
    fi
}

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 \"VM_URL\""
    echo
    echo "Example:"
    echo "  $0 \"https://console.cloud.google.com/compute/instancesDetail/zones/asia-south1-a/instances/kafka-connect-1?project=prod\""
    echo
    echo "Note: Handles escaped URLs from Mac terminal (\\? becomes ?)"
    exit 1
fi

check_prerequisites
main "$1"
