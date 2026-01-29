#!/bin/bash

###############################################################################
# GCP Disk Expander Tool
# Expands GCP disks and their filesystems automatically
#
# Usage:
#   ./disk_expander.sh <gcp-console-url>
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
        RESOURCE_TYPE="vm"
        ZONE="${BASH_REMATCH[1]}"
        RESOURCE_NAME="${BASH_REMATCH[2]}"
        
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
    
    # Disk URL pattern: zones/ZONE/disks/DISK-NAME
    if [[ $url =~ zones/([^/\?#]+)/disks/([^/\?#]+) ]]; then
        RESOURCE_TYPE="disk"
        ZONE="${BASH_REMATCH[1]}"
        RESOURCE_NAME="${BASH_REMATCH[2]}"
        
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
    
    print_error "URL does not match VM or Disk pattern"
    return 1
}

# Function to get disk information
get_disk_info() {
    local project="$1"
    local zone="$2"
    local disk_name="$3"
    
    gcloud compute disks describe "$disk_name" \
        --project="$project" \
        --zone="$zone" \
        --format="json" 2>/dev/null
}

# Function to get current disk size
get_disk_size() {
    local project="$1"
    local zone="$2"
    local disk_name="$3"
    
    gcloud compute disks describe "$disk_name" \
        --project="$project" \
        --zone="$zone" \
        --format="value(sizeGb)" 2>/dev/null
}

# Function to list VM disks
list_vm_disks() {
    local project="$1"
    local zone="$2"
    local vm_name="$3"
    
    gcloud compute instances describe "$vm_name" \
        --project="$project" \
        --zone="$zone" \
        --format="json" 2>/dev/null | \
        jq -r '.disks[] | "\(.index)|\(.deviceName)|\(.source | split("/")[-1])"'
}

# Function to get VM for a disk
get_vm_for_disk() {
    local project="$1"
    local zone="$2"
    local disk_name="$3"
    
    local disk_info=$(get_disk_info "$project" "$zone" "$disk_name")
    local users=$(echo "$disk_info" | jq -r '.users[]?' 2>/dev/null)
    
    if [[ -z "$users" ]]; then
        return 1
    fi
    
    # Extract VM name from user URL using sed instead of grep -P
    echo "$users" | head -n1 | sed -n 's|.*/instances/\([^/]*\)$|\1|p'
}

# Function to expand disk in GCP
expand_disk_gcp() {
    local project="$1"
    local zone="$2"
    local disk_name="$3"
    local new_size="$4"
    
    print_info "Expanding disk '$disk_name' to ${new_size}GB in GCP..."
    
    if gcloud compute disks resize "$disk_name" \
        --size="${new_size}GB" \
        --project="$project" \
        --zone="$zone" \
        --quiet 2>/dev/null; then
        print_success "Disk expanded successfully in GCP"
        return 0
    else
        print_error "Failed to expand disk in GCP"
        return 1
    fi
}

# Function to expand filesystem inside VM
expand_filesystem() {
    local vm="$1"
    local project="$2"
    local zone="$3"
    local disk_name="$4"
    
    print_header "Expanding Filesystem Inside VM"
    
    print_info "Detecting device for disk: $disk_name"
    
    # Create the expansion script
    cat > /tmp/expand_fs.sh << 'EOF'
#!/bin/bash
set -e

DISK_NAME="$1"

echo "Searching for device with disk name: $DISK_NAME"

# Install required packages
echo "Installing required utilities..."
if command -v apt-get &> /dev/null; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cloud-utils cloud-guest-utils -qq 2>/dev/null
elif command -v yum &> /dev/null; then
    sudo yum install -y cloud-utils-growpart gdisk -q 2>/dev/null
fi

# Find the device by disk name in /dev/disk/by-id/
DEVICE=""
DEVICE_LINK="/dev/disk/by-id/google-${DISK_NAME}"

if [[ -L "$DEVICE_LINK" ]]; then
    DEVICE=$(readlink -f "$DEVICE_LINK")
    echo "Found device: $DEVICE (via $DEVICE_LINK)"
else
    echo "ERROR: Could not find device link: $DEVICE_LINK"
    echo "Available disks in /dev/disk/by-id/:"
    ls -la /dev/disk/by-id/ | grep google || true
    exit 1
fi

# Check for partition 1
PARTITION=""
if [[ -b "${DEVICE}1" ]]; then
    PARTITION="${DEVICE}1"
elif [[ -b "${DEVICE}p1" ]]; then
    # NVMe style
    PARTITION="${DEVICE}p1"
fi

# Determine which to expand - partition or whole disk
TARGET_DEVICE=""
if [[ -n "$PARTITION" ]]; then
    # Check if partition has filesystem
    if sudo blkid "$PARTITION" &>/dev/null; then
        TARGET_DEVICE="$PARTITION"
        echo "Using partition: $TARGET_DEVICE"
    else
        TARGET_DEVICE="$DEVICE"
        echo "Partition exists but no filesystem, using whole disk: $TARGET_DEVICE"
    fi
else
    TARGET_DEVICE="$DEVICE"
    echo "No partition found, using whole disk: $TARGET_DEVICE"
fi

# Get filesystem type using blkid
FS_TYPE=$(sudo blkid -o value -s TYPE "$TARGET_DEVICE" 2>/dev/null || echo "unknown")
echo "Detected filesystem: $FS_TYPE"

# Get mount point
MOUNT_POINT=$(lsblk -no MOUNTPOINT "$TARGET_DEVICE" 2>/dev/null | head -n1)
echo "Mount point: ${MOUNT_POINT:-not mounted}"

if [[ -z "$MOUNT_POINT" ]]; then
    echo "WARNING: Device is not mounted. Cannot expand filesystem."
    exit 1
fi

# Grow partition if we're using a partition
if [[ "$TARGET_DEVICE" == *[0-9] ]] || [[ "$TARGET_DEVICE" == *p[0-9] ]]; then
    # Extract base device and partition number
    if [[ "$TARGET_DEVICE" =~ ^(.*)([0-9]+)$ ]]; then
        BASE_DEVICE="${BASH_REMATCH[1]}"
        PARTITION_NUM="${BASH_REMATCH[2]}"
        
        # Remove trailing 'p' for nvme devices
        if [[ "$BASE_DEVICE" == *p ]]; then
            BASE_DEVICE="${BASE_DEVICE%p}"
        fi
        
        echo "Growing partition $PARTITION_NUM on $BASE_DEVICE..."
        sudo growpart "$BASE_DEVICE" "$PARTITION_NUM" 2>&1 || echo "Note: Partition may already be at maximum size"
    fi
fi

# Expand filesystem based on type
echo ""
case "$FS_TYPE" in
    ext4|ext3|ext2)
        echo "Expanding ext filesystem on $TARGET_DEVICE..."
        sudo resize2fs "$TARGET_DEVICE"
        ;;
    xfs)
        echo "Expanding XFS filesystem on mount point: $MOUNT_POINT..."
        sudo xfs_growfs "$MOUNT_POINT"
        ;;
    btrfs)
        echo "Expanding Btrfs filesystem on mount point: $MOUNT_POINT..."
        sudo btrfs filesystem resize max "$MOUNT_POINT"
        ;;
    *)
        echo "ERROR: Unknown or unsupported filesystem type: $FS_TYPE"
        exit 1
        ;;
esac

echo ""
echo "✓ Filesystem expanded successfully!"
echo ""
echo "Updated disk information:"
lsblk "$TARGET_DEVICE" -o NAME,SIZE,FSTYPE,MOUNTPOINT
echo ""
echo "Disk usage:"
df -h "$MOUNT_POINT"
EOF

    # Copy script to VM and execute
    print_info "Copying expansion script to VM..."
    
    if gcloud compute scp /tmp/expand_fs.sh "$vm:/tmp/expand_fs.sh" \
        --project="$project" \
        --zone="$zone" \
        --quiet 2>/dev/null; then
        
        print_info "Executing filesystem expansion..."
        
        if gcloud compute ssh "$vm" \
            --project="$project" \
            --zone="$zone" \
            --command="bash /tmp/expand_fs.sh '$disk_name' && rm /tmp/expand_fs.sh"; then
            print_success "Filesystem expanded successfully!"
            rm /tmp/expand_fs.sh
            return 0
        fi
    fi
    
    print_error "Failed to expand filesystem"
    rm -f /tmp/expand_fs.sh
    return 1
}

# Function to prompt for device selection - REMOVED (no longer needed)
select_device_interactive() {
    echo "This function is deprecated"
}

# Main function
main() {
    print_header "GCP Disk Expander Tool"
    
    # Check if URL argument is provided
    if [[ $# -ne 1 ]]; then
        echo "Usage: $0 <gcp-console-url>"
        echo ""
        echo "Example URLs:"
        echo "  VM:   https://console.cloud.google.com/compute/instancesDetail/zones/us-central1-a/instances/my-vm?project=my-project"
        echo "  Disk: https://console.cloud.google.com/compute/disksDetail/zones/us-central1-a/disks/my-disk?project=my-project"
        exit 1
    fi
    
    local url="$1"
    local PROJECT=""
    local ZONE=""
    local RESOURCE_TYPE=""
    local RESOURCE_NAME=""
    
    # Parse URL
    if ! parse_gcp_url "$url"; then
        print_error "Invalid GCP URL format"
        echo ""
        echo "Expected format:"
        echo "  VM:   https://console.cloud.google.com/compute/.../projects/PROJECT/zones/ZONE/instances/VM-NAME"
        echo "  Disk: https://console.cloud.google.com/compute/.../projects/PROJECT/zones/ZONE/disks/DISK-NAME"
        exit 1
    fi
    
    print_info "Project: $PROJECT"
    print_info "Zone: $ZONE"
    print_info "Resource Type: $RESOURCE_TYPE"
    print_info "Resource Name: $RESOURCE_NAME"
    
    # Handle based on resource type
    if [[ "$RESOURCE_TYPE" == "disk" ]]; then
        print_header "Direct Disk Expansion"
        
        DISK_NAME="$RESOURCE_NAME"
        
        # Get current disk size
        CURRENT_SIZE=$(get_disk_size "$PROJECT" "$ZONE" "$DISK_NAME")
        if [[ -z "$CURRENT_SIZE" ]]; then
            print_error "Could not get disk information"
            exit 1
        fi
        
        echo -e "${BOLD}Disk:${NC} $DISK_NAME"
        echo -e "${BOLD}Current Size:${NC} ${CURRENT_SIZE}GB"
        echo ""
        
        # Ask for new size
        read -p "Enter new size in GB (must be larger than ${CURRENT_SIZE}GB): " NEW_SIZE
        
        if [[ ! "$NEW_SIZE" =~ ^[0-9]+$ ]]; then
            print_error "Invalid size. Please enter a number."
            exit 1
        fi
        
        if [[ $NEW_SIZE -le $CURRENT_SIZE ]]; then
            print_error "New size must be larger than current size (${CURRENT_SIZE}GB)"
            exit 1
        fi
        
        # Expand disk
        if ! expand_disk_gcp "$PROJECT" "$ZONE" "$DISK_NAME" "$NEW_SIZE"; then
            exit 1
        fi
        
        # Check if disk is attached to a VM
        print_info "Checking if disk is attached to a VM..."
        VM_NAME=$(get_vm_for_disk "$PROJECT" "$ZONE" "$DISK_NAME")
        
        if [[ -z "$VM_NAME" ]]; then
            print_warning "Disk is not attached to any VM"
            print_info "Disk resized in GCP. Attach it to a VM and run filesystem expansion manually."
            exit 0
        fi
        
        print_info "Disk is attached to VM: $VM_NAME"
        
        # Ask if user wants to expand filesystem
        read -p "Do you want to expand the filesystem inside the VM? (y/n): " EXPAND_FS
        
        if [[ "$EXPAND_FS" =~ ^[Yy]$ ]]; then
            expand_filesystem "$VM_NAME" "$PROJECT" "$ZONE" "$DISK_NAME"
        fi
        
    elif [[ "$RESOURCE_TYPE" == "vm" ]]; then
        print_header "VM Disk Expansion"
        
        VM_NAME="$RESOURCE_NAME"
        
        # List all disks attached to VM
        print_info "Fetching disks attached to VM: $VM_NAME"
        echo ""
        
        DISK_LIST=$(list_vm_disks "$PROJECT" "$ZONE" "$VM_NAME")
        
        if [[ -z "$DISK_LIST" ]]; then
            print_error "No disks found or could not retrieve VM information"
            exit 1
        fi
        
        echo -e "${BOLD}Attached Disks:${NC}"
        echo "-------------------------------------------"
        printf "%-5s %-20s %-20s\n" "Index" "Device Name" "Disk Name"
        echo "-------------------------------------------"
        
        while IFS='|' read -r index device_name disk_name; do
            # Get disk size
            disk_size=$(get_disk_size "$PROJECT" "$ZONE" "$disk_name")
            printf "%-5s %-20s %-20s (%sGB)\n" "$index" "$device_name" "$disk_name" "$disk_size"
        done <<< "$DISK_LIST"
        
        echo ""
        read -p "Enter the disk name (or index number) to expand: " DISK_INPUT
        
        # Check if input is a number (index) or disk name
        if [[ "$DISK_INPUT" =~ ^[0-9]+$ ]]; then
            # User entered an index, find the corresponding disk name
            DISK_NAME=$(echo "$DISK_LIST" | awk -F'|' -v idx="$DISK_INPUT" '$1 == idx {print $3}')
            if [[ -z "$DISK_NAME" ]]; then
                print_error "Invalid index: $DISK_INPUT"
                exit 1
            fi
            print_info "Selected disk: $DISK_NAME"
        else
            # User entered disk name directly
            DISK_NAME="$DISK_INPUT"
        fi
        
        # Get current disk size
        CURRENT_SIZE=$(get_disk_size "$PROJECT" "$ZONE" "$DISK_NAME")
        if [[ -z "$CURRENT_SIZE" ]]; then
            print_error "Could not get disk information for: $DISK_NAME"
            exit 1
        fi
        
        echo -e "${BOLD}Current Size:${NC} ${CURRENT_SIZE}GB"
        echo ""
        
        # Ask for new size
        read -p "Enter new size in GB (must be larger than ${CURRENT_SIZE}GB): " NEW_SIZE
        
        if [[ ! "$NEW_SIZE" =~ ^[0-9]+$ ]]; then
            print_error "Invalid size. Please enter a number."
            exit 1
        fi
        
        if [[ $NEW_SIZE -le $CURRENT_SIZE ]]; then
            print_error "New size must be larger than current size (${CURRENT_SIZE}GB)"
            exit 1
        fi
        
        # Expand disk
        if ! expand_disk_gcp "$PROJECT" "$ZONE" "$DISK_NAME" "$NEW_SIZE"; then
            exit 1
        fi
        
        # Expand filesystem
        read -p "Do you want to expand the filesystem inside the VM? (y/n): " EXPAND_FS
        
        if [[ "$EXPAND_FS" =~ ^[Yy]$ ]]; then
            expand_filesystem "$VM_NAME" "$PROJECT" "$ZONE" "$DISK_NAME"
        fi
    else
        print_error "Unknown resource type"
        exit 1
    fi
    
    print_header "Summary"
    print_success "All operations completed successfully!"
    echo -e "${BOLD}Disk:${NC} $DISK_NAME"
    echo -e "${BOLD}Old Size:${NC} ${CURRENT_SIZE}GB"
    echo -e "${BOLD}New Size:${NC} ${NEW_SIZE}GB"
    echo ""
}

# Run main function
main "$@"
