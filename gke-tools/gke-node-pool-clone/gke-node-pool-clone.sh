#!/bin/bash
# ./cls.sh <URL>  2>&1 | ts '%Y-%m-%d %H:%M:%S' | tee analytics.log
set -euo pipefail

# ============================
#  GKE Node Pool Clone Helper
# ============================
# Requires: gcloud, jq

if ! command -v jq &>/dev/null; then
  echo "ERROR: 'jq' is required. Install it first."
  exit 1
fi
if ! command -v gcloud &>/dev/null; then
  echo "ERROR: 'gcloud' is required. Install/authorize it first."
  exit 1
fi

URL="$1"

if [ -z "${URL:-}" ]; then
  echo "Usage: $0 <gke-console-nodepool-url>"
  exit 1
fi

echo "Sanitizing URL..."
# Remove shell-added escapes like \? \= \/
URL=$(printf '%s' "$URL" | sed 's/\\//g')
# Trim trailing slashes/backslashes
URL=$(printf '%s' "$URL" | sed 's/[\/\\]*$//')

echo "Parsing URL..."
SECTION=$(printf '%s' "$URL" | awk -F'/kubernetes/nodepool/' '{print $2}')
LOCATION=$(printf '%s' "$SECTION" | cut -d'/' -f1)
CLUSTER=$(printf '%s' "$SECTION" | cut -d'/' -f2)
NODEPOOL=$(printf '%s' "$SECTION" | cut -d'/' -f3 | cut -d'?' -f1)
PROJECT=$(printf '%s' "$URL" | grep -oE 'project=[^&]+' | cut -d'=' -f2 || true)

echo "Parsed Values:"
echo "  Project   : $PROJECT"
echo "  Location  : $LOCATION"
echo "  Cluster   : $CLUSTER"
echo "  Node Pool : $NODEPOOL"
echo

if [ -z "$PROJECT" ] || [ -z "$LOCATION" ] || [ -z "$CLUSTER" ] || [ -z "$NODEPOOL" ]; then
  echo "❌ ERROR: Failed to extract required values from URL. Ensure URL looks like:"
  echo "https://console.cloud.google.com/kubernetes/nodepool/<location>/<cluster>/<nodepool>?project=<project>"
  exit 1
fi

echo "Fetching node pool details (one time)..."
if ! gcloud container node-pools describe "$NODEPOOL" \
    --cluster "$CLUSTER" \
    --location "$LOCATION" \
    --project "$PROJECT" \
    --format json > nodepool.json 2>nodepool.describe.err; then
  echo "ERROR: gcloud failed. See nodepool.describe.err"
  sed -n '1,200p' nodepool.describe.err
  exit 1
fi

# Validate nodepool.json
if ! jq empty nodepool.json >/dev/null 2>&1; then
  echo "ERROR: nodepool.json is not valid JSON"
  head -n 50 nodepool.json
  exit 1
fi

echo "Saved nodepool.json"
echo

echo "Extracting values from nodepool.json..."
# machine/disk/image
MACHINE_TYPE=$(jq -r '.config.machineType // .nodeConfig.machineType // empty' nodepool.json)
DISK_SIZE=$(jq -r '.config.diskSizeGb // .nodeConfig.diskSizeGb // empty' nodepool.json)
DISK_TYPE=$(jq -r '.config.diskType // .nodeConfig.diskType // empty' nodepool.json)
IMAGE_TYPE=$(jq -r '.config.imageType // .nodeConfig.imageType // empty' nodepool.json)

# scopes & service account
SCOPES=$(jq -r '(.config.oauthScopes // .nodeConfig.oauthScopes // []) | join(",")' nodepool.json)
#SCOPES='https://www.googleapis.com/auth/cloud-platform'
SERVICE_ACCOUNT=$(jq -r '.config.serviceAccount // .nodeConfig.serviceAccount // empty' nodepool.json)

# taints (joined by comma)
TAINTS=$(jq -r '
  (.config.taints // .nodeConfig.taints // []) 
  | map(
      .key + "=" + (.value // "") + ":" +
      (
        if .effect == "NO_SCHEDULE" then "NoSchedule"
        elif .effect == "NO_EXECUTE" then "NoExecute"
        elif .effect == "PREFER_NO_SCHEDULE" then "PreferNoSchedule"
        else .effect
        end
      )
    )
  | join(",")
' nodepool.json)
[ "$TAINTS" = "null" ] && TAINTS=""

# labels: use config.resourceLabels OR config.labels OR resourceLabels; filter out goog-gke*
LABELS=$(jq -r '
  (
    (.config.resourceLabels // .config.labels // .resourceLabels // {} )
  )
  | to_entries
  | map(select(.key | startswith("goog-gke") | not))
  | map("\(.key)=\(.value)")
  | join(",")
' nodepool.json)
[ "$LABELS" = "null" ] && LABELS=""

# node version fallback: prefer cluster version (must use cluster version), fallback to nodepool
NODEPOOL_NODE_VERSION=$(jq -r '.version // empty' nodepool.json)

# get cluster version (currentMasterVersion). If fails, fall back to nodepool version
CLUSTER_VERSION=$(gcloud container clusters describe "$CLUSTER" --project "$PROJECT" --location "$LOCATION" --format="value(currentMasterVersion)" 2>/dev/null || true)
if [ -z "$CLUSTER_VERSION" ]; then
  CLUSTER_VERSION="$NODEPOOL_NODE_VERSION"
fi

# num nodes / max pods (handle multiple possible paths)
NUM_NODES=$(jq -r '.initialNodeCount // .config.initialNodeCount // empty' nodepool.json)
MAX_PODS=$(jq -r '.config.maxPodsPerNode // .maxPodsConstraint.maxPodsPerNode // empty' nodepool.json)

# autoscaling
AUTOSCALING_ENABLED=$(jq -r '.autoscaling.enabled // false' nodepool.json)
MIN_NODES=$(jq -r '.autoscaling.minNodeCount // empty' nodepool.json)
MAX_NODES=$(jq -r '.autoscaling.maxNodeCount // empty' nodepool.json)

# management flags (autoUpgrade/autoRepair)
AUTO_UPGRADE=$(jq -r '.management.autoUpgrade // false' nodepool.json)
AUTO_REPAIR=$(jq -r '.management.autoRepair // false' nodepool.json)

# upgrade settings
MAX_SURGE=$(jq -r '.upgradeSettings.maxSurge // 0' nodepool.json)
MAX_UNAVAILABLE=$(jq -r '.upgradeSettings.maxUnavailable // 0' nodepool.json)

# metadata: disable-legacy-endpoints
METADATA_DISABLE_LEGACY=$(jq -r '.config.metadata."disable-legacy-endpoints" // .metadata."disable-legacy-endpoints" // empty' nodepool.json)

# pod-ipv4-range name (podRange) OR podIpv4CidrBlock
POD_RANGE_NAME=$(jq -r '.networkConfig.podRange // empty' nodepool.json)
POD_IPV4_CIDR=$(jq -r '.networkConfig.podIpv4CidrBlock // empty' nodepool.json)

# node-locations (array -> comma list)
NODE_LOCATIONS=$(jq -r '(.locations // []) | join(",")' nodepool.json)

# Debug prints
echo "Machine Type     : $MACHINE_TYPE"
echo "Disk Size (GB)   : $DISK_SIZE"
echo "Disk Type        : $DISK_TYPE"
echo "Image Type       : $IMAGE_TYPE"
echo "Scopes           : $SCOPES"
echo "Service Account  : $SERVICE_ACCOUNT"
echo "Taints           : $TAINTS"
echo "Labels           : $LABELS"
echo "Cluster Version  : $CLUSTER_VERSION"
echo "Node Version (pool): $NODEPOOL_NODE_VERSION"
echo "Num Nodes        : $NUM_NODES"
echo "Max Pods/Node    : $MAX_PODS"
echo "Autoscaling      : $AUTOSCALING_ENABLED"
echo "Min Nodes        : $MIN_NODES"
echo "Max Nodes        : $MAX_NODES"
echo "AutoUpgrade      : $AUTO_UPGRADE"
echo "AutoRepair       : $AUTO_REPAIR"
echo "Max Surge        : $MAX_SURGE"
echo "Max Unavailable  : $MAX_UNAVAILABLE"
echo "Metadata disable-legacy-endpoints : $METADATA_DISABLE_LEGACY"
echo "Pod Range name   : $POD_RANGE_NAME"
echo "Pod IPv4 CIDR    : $POD_IPV4_CIDR"
echo "Node Locations   : $NODE_LOCATIONS"
echo

echo "Node Pool Info Extraction Complete"
echo
echo "Enter NEW NodePool name: "
#read -p "Enter NEW NodePool name: " NEW_NP
read NEW_NP
echo "selected Name: $NEW_NP"
SCRIPT="create-${NEW_NP}.sh"
echo "#!/bin/bash" > "$SCRIPT"

# Build a list of printf lines for safe newline handling
lines=()

lines+=("gcloud container node-pools create \"${NEW_NP}\" \\" )
lines+=("  --project \"${PROJECT}\" \\" )
lines+=("  --cluster \"${CLUSTER}\" \\" )
lines+=("  --location \"${LOCATION}\" \\" )
[ -n "$MACHINE_TYPE" ] && lines+=("  --machine-type \"${MACHINE_TYPE}\" \\" )
[ -n "$DISK_SIZE" ] && lines+=("  --disk-size \"${DISK_SIZE}\" \\" )
[ -n "$DISK_TYPE" ] && lines+=("  --disk-type \"${DISK_TYPE}\" \\" )
[ -n "$IMAGE_TYPE" ] && lines+=("  --image-type \"${IMAGE_TYPE}\" \\" )

# Use cluster version (guaranteed to be compatible)
[ -n "$CLUSTER_VERSION" ] && lines+=("  --node-version \"${CLUSTER_VERSION}\" \\" )

[ -n "$NUM_NODES" ] && lines+=("  --num-nodes \"${NUM_NODES}\" \\" )
[ -n "$MAX_PODS" ] && lines+=("  --max-pods-per-node \"${MAX_PODS}\" \\" )
[ -n "$SERVICE_ACCOUNT" ] && lines+=("  --service-account \"${SERVICE_ACCOUNT}\" \\" )
[ -n "$SCOPES" ] && lines+=("  --scopes \"${SCOPES}\" \\" )

# labels/taints only if non-empty
if [ -n "$LABELS" ]; then
  lines+=("  --labels \"${LABELS}\" \\" )
fi
if [ -n "$TAINTS" ]; then
  lines+=("  --node-taints \"${TAINTS}\" \\" )
fi

# pod-ipv4-range: prefer podRange name (secondary range), else use cidr block (not typical for flag)
if [ -n "$POD_RANGE_NAME" ]; then
  lines+=("  --pod-ipv4-range \"${POD_RANGE_NAME}\" \\" )
elif [ -n "$POD_IPV4_CIDR" ]; then
  # gcloud expects a secondary range name, but include CIDR as comment fallback
  lines+=("  --comment \"podIpv4CidrBlock:${POD_IPV4_CIDR}\" \\" )
fi

# node-locations
if [ -n "$NODE_LOCATIONS" ]; then
  lines+=("  --node-locations \"${NODE_LOCATIONS}\" \\" )
fi

# management flags
if [ "$AUTO_UPGRADE" = "true" ]; then
  lines+=("  --enable-autoupgrade \\" )
else
  lines+=("  --no-enable-autoupgrade \\" )
fi
if [ "$AUTO_REPAIR" = "true" ]; then
  lines+=("  --enable-autorepair \\" )
else
  lines+=("  --no-enable-autorepair \\" )
fi

# autoscaling
if [ "$AUTOSCALING_ENABLED" = "true" ]; then
  lines+=("  --enable-autoscaling \\" )
  [ -n "$MIN_NODES" ] && lines+=("  --min-nodes \"${MIN_NODES}\" \\" )
  [ -n "$MAX_NODES" ] && lines+=("  --max-nodes \"${MAX_NODES}\" \\" )
else
  lines+=("  --no-enable-autoscaling \\" )
fi

# upgrade settings
[ -n "$MAX_SURGE" ] && lines+=("  --max-surge-upgrade \"${MAX_SURGE}\" \\" )
[ -n "$MAX_UNAVAILABLE" ] && lines+=("  --max-unavailable-upgrade \"${MAX_UNAVAILABLE}\" \\" )

# metadata flag
if [ "$METADATA_DISABLE_LEGACY" = "true" ]; then
  lines+=("  --metadata disable-legacy-endpoints=true" )
fi

# Print lines into script with proper newlines
for ln in "${lines[@]}"; do
  printf '%s\n' "$ln" >> "$SCRIPT"
done

chmod +x "$SCRIPT"
echo
echo "Node Pool Creation Script Generated: $SCRIPT"
echo
echo "Do you want to EXECUTE the script now? (y/n): "
#read -p "Do you want to EXECUTE the script now? (y/n): " RUN
read RUN
echo "selected Value: $RUN"
RUN_LOWER=$(printf "%s" "$RUN" | tr '[:upper:]' '[:lower:]')
if [[ "$RUN_LOWER" == "y" ]]; then
  bash "$SCRIPT"
else
  echo "Run manually with: bash $SCRIPT"
fi

#rm -rf nodepool.json
