#!/bin/bash

# Script to apply IAM roles to multiple GCP projects
# Usage: ./iam_roles_apply.sh <member>
# Example: ./iam_roles_apply.sh serviceAccount:prometheus-sa@monitoring-project.iam.gserviceaccount.com
# Example: ./iam_roles_apply.sh user:john.doe@example.com
# Example: ./iam_roles_apply.sh group:devops-team@example.com

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fixed filenames in the same directory as the script
ROLES_FILE="${SCRIPT_DIR}/roles.txt"
PROJECTS_FILE="${SCRIPT_DIR}/projects.txt"

# Function to display usage
usage() {
    echo "Usage: $0 <member>"
    echo ""
    echo "Arguments:"
    echo "  member  - Member in format 'type:identifier'"
    echo "            Types: serviceAccount, user, or group"
    echo ""
    echo "Required files (must be in the same directory as script):"
    echo "  roles.txt     - File containing list of roles (one per line)"
    echo "  projects.txt  - File containing list of project IDs (one per line)"
    echo ""
    echo "Examples:"
    echo "  $0 serviceAccount:prometheus-sa@monitoring-project.iam.gserviceaccount.com"
    echo "  $0 user:john.doe@example.com"
    echo "  $0 group:devops-team@example.com"
    exit 1
}

# Check if correct number of arguments provided
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Error: Invalid number of arguments${NC}"
    usage
fi

MEMBER=$1

# Validate member format (must contain a colon and be one of the valid types)
if [[ ! "$MEMBER" =~ ^(serviceAccount|user|group):.+$ ]]; then
    echo -e "${RED}Error: Invalid member format${NC}"
    echo -e "${RED}Must be in format: type:identifier${NC}"
    echo -e "${RED}Valid types: serviceAccount, user, group${NC}"
    echo ""
    echo "Examples:"
    echo "  user:jane@example.com"
    echo "  serviceAccount:sa@project.iam.gserviceaccount.com"
    echo "  group:team@example.com"
    usage
fi

# Check if files exist
if [ ! -f "$ROLES_FILE" ]; then
    echo -e "${RED}Error: Roles file '$ROLES_FILE' not found${NC}"
    echo "Please create 'roles.txt' in the same directory as this script"
    exit 1
fi

if [ ! -f "$PROJECTS_FILE" ]; then
    echo -e "${RED}Error: Projects file '$PROJECTS_FILE' not found${NC}"
    echo "Please create 'projects.txt' in the same directory as this script"
    exit 1
fi

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI is not installed${NC}"
    exit 1
fi

echo -e "${YELLOW}======================================${NC}"
echo -e "${YELLOW}IAM Role Binding Automation${NC}"
echo -e "${YELLOW}======================================${NC}"
echo -e "Roles file: ${GREEN}$ROLES_FILE${NC}"
echo -e "Projects file: ${GREEN}$PROJECTS_FILE${NC}"
echo -e "Member: ${GREEN}$MEMBER${NC}"
echo -e "${YELLOW}======================================${NC}"
echo ""

# Read roles into array (POSIX-compatible way)
ROLES=()
while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]] && continue
    # Trim whitespace
    line=$(echo "$line" | xargs)
    ROLES+=("$line")
done < "$ROLES_FILE"

echo -e "Found ${GREEN}${#ROLES[@]}${NC} roles to apply"

# Read projects into array (POSIX-compatible way)
PROJECTS=()
while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]] && continue
    # Trim whitespace
    line=$(echo "$line" | xargs)
    PROJECTS+=("$line")
done < "$PROJECTS_FILE"

echo -e "Found ${GREEN}${#PROJECTS[@]}${NC} projects"
echo ""

# Counters for summary
TOTAL_OPERATIONS=$((${#ROLES[@]} * ${#PROJECTS[@]}))
SUCCESS_COUNT=0
FAILURE_COUNT=0

# Log file
LOG_FILE="iam_binding_$(date +%Y%m%d_%H%M%S).log"
echo "Logging to: $LOG_FILE"
echo ""

# Confirmation prompt
read -p "Do you want to proceed? (yes/no): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Operation cancelled${NC}"
    exit 0
fi

echo "" | tee -a "$LOG_FILE"
echo "Starting IAM policy binding..." | tee -a "$LOG_FILE"
echo "Timestamp: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Apply roles to projects
for PROJECT in "${PROJECTS[@]}"; do
    # Skip empty lines and comments
    [[ -z "$PROJECT" || "$PROJECT" =~ ^#.*$ ]] && continue
    
    # Trim whitespace
    PROJECT=$(echo "$PROJECT" | xargs)
    
    echo -e "${YELLOW}Processing project: $PROJECT${NC}" | tee -a "$LOG_FILE"
    
    for ROLE in "${ROLES[@]}"; do
        # Skip empty lines and comments
        [[ -z "$ROLE" || "$ROLE" =~ ^#.*$ ]] && continue
        
        # Trim whitespace
        ROLE=$(echo "$ROLE" | xargs)
        
        echo -n "  Applying role: $ROLE ... " | tee -a "$LOG_FILE"
        
        # Execute the gcloud command
        if gcloud projects add-iam-policy-binding "$PROJECT" \
            --member="$MEMBER" \
            --role="$ROLE" \
            --condition=None \
            >> "$LOG_FILE" 2>&1; then
            echo -e "${GREEN}SUCCESS${NC}" | tee -a "$LOG_FILE"
            ((SUCCESS_COUNT++))
        else
            echo -e "${RED}FAILED${NC}" | tee -a "$LOG_FILE"
            ((FAILURE_COUNT++))
        fi
    done
    echo "" | tee -a "$LOG_FILE"
done

# Summary
echo -e "${YELLOW}======================================${NC}" | tee -a "$LOG_FILE"
echo -e "${YELLOW}Summary${NC}" | tee -a "$LOG_FILE"
echo -e "${YELLOW}======================================${NC}" | tee -a "$LOG_FILE"
echo -e "Total operations: $TOTAL_OPERATIONS" | tee -a "$LOG_FILE"
echo -e "Successful: ${GREEN}$SUCCESS_COUNT${NC}" | tee -a "$LOG_FILE"
echo -e "Failed: ${RED}$FAILURE_COUNT${NC}" | tee -a "$LOG_FILE"
echo -e "${YELLOW}======================================${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Detailed log saved to: $LOG_FILE"

# Exit with error code if there were failures
if [ $FAILURE_COUNT -gt 0 ]; then
    exit 1
fi
