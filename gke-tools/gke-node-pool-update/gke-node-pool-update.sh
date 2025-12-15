#!/bin/bash

set -e

# ============================
# GKE Node Pool Machine-Type Updater
# (URL based, disk preserved)
# ============================

if ! command -v jq &>/dev/null; then
  echo "❌ jq is required"
  exit 1
fi

URL="$1"

if [[ -z "$URL" ]]; then
  echo "Usage:"
  echo "  ./gke-node-pool-update.sh <GKE_NODEPOOL_CONSOLE_URL>"
  exit 1
fi

echo "============================================"
echo " Sanitizing & Parsing GKE URL"
echo "============================================"

URL=$(echo "$URL" | sed 's/\\//g')

SECTION=$(echo "$URL" | awk -F'/kubernetes/nodepool/' '{print $2}')

REGION=$(echo "$SECTION" | cut -d'/' -f1)
CLUSTER=$(echo "$SECTION" | cut -d'/' -f2)
NODEPOOL=$(echo "$SECTION" | cut -d'/' -f3 | cut -d'?' -f1)
PROJECT=$(echo "$URL" | grep -oE 'project=[^&]+' | cut -d'=' -f2)

echo
echo "Parsed Values"
echo "--------------------------------------------"
echo " Project  : $PROJECT"
echo " Region   : $REGION"
echo " Cluster  : $CLUSTER"
echo " NodePool : $NODEPOOL"
echo "--------------------------------------------"
echo

if [[ -z "$PROJECT" || -z "$REGION" || -z "$CLUSTER" || -z "$NODEPOOL" ]]; then
  echo "❌ Failed to parse URL"
  exit 1
fi

echo "Fetching current node pool configuration..."
echo

NP_JSON=$(gcloud container node-pools describe "$NODEPOOL" \
  --cluster "$CLUSTER" \
  --region "$REGION" \
  --project "$PROJECT" \
  --format=json)

CUR_MACHINE=$(echo "$NP_JSON" | jq -r '.config.machineType')
CUR_DISK=$(echo "$NP_JSON" | jq -r '.config.diskSizeGb')

echo "============================================"
echo " Current Configuration"
echo "============================================"
echo " Machine Type : $CUR_MACHINE"
echo " Disk Size    : ${CUR_DISK}GB"
echo "============================================"
echo

read -p "New Machine Type : " NEW_MACHINE

if [[ -z "$NEW_MACHINE" ]]; then
  echo
  echo "❌ No machine type entered."
  echo "Exiting safely without updating or generating script."
  exit 0
fi

NEW_MACHINE=${NEW_MACHINE:-$CUR_MACHINE}

echo
echo "============================================"
echo " Proposed Update"
echo "============================================"
echo " Machine Type : $CUR_MACHINE -> $NEW_MACHINE"
echo "============================================"
echo

read -p "Apply update now? (y/n): " CONFIRM

SCRIPT="update-${NODEPOOL}.sh"

cat <<EOF > "$SCRIPT"
#!/bin/bash
gcloud container node-pools update "$NODEPOOL" \\
  --cluster "$CLUSTER" \\
  --region "$REGION" \\
  --project "$PROJECT" \\
  --machine-type "$NEW_MACHINE" \\
  --disk-size "${CUR_DISK}GB"
EOF

chmod +x "$SCRIPT"

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo
  echo "🚀 Executing update..."
  bash "$SCRIPT"
else
  echo
  echo "📝 Script generated, not executed:"
  echo "  ./$SCRIPT"
fi
