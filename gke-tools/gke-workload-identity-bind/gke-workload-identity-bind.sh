#!/usr/bin/env bash
set -euo pipefail
echo "======================================"
echo "Make Sure you are in correct k8s context"
echo "======================================"

# ==============================
# Input
# ==============================
if [[ -n "$1" ]]; then
  IFS=',' read -r PROJECT NAMESPACE A B <<< "$1"

  if [[ -z "$B" ]]; then
    # Format: PROJECT,NAMESPACE,GSA
    GSA="$A"
    KSA="$A"
  else
    # Format: PROJECT,NAMESPACE,KSA,GSA
    KSA="$A"
    GSA="$B"
  fi
else
  read -p "Project ID              : " PROJECT
  read -p "Namespace               : " NAMESPACE
  read -p "Kubernetes SA (optional): " KSA
  read -p "GCP Service Account     : " GSA
fi

[[ -z "${PROJECT:-}" || -z "${NAMESPACE:-}" || -z "${GSA:-}" ]] && {
  echo "❌ PROJECT, NAMESPACE, GSA are required"
  exit 1
}

KSA="${KSA:-$GSA}"
GSA_EMAIL="$GSA@$PROJECT.iam.gserviceaccount.com"

echo "======================================"
echo "🔐 GKE Workload Identity Planner"
echo "======================================"
echo "Project   : $PROJECT"
echo "Namespace : $NAMESPACE"
echo "KSA       : $KSA"
echo "GSA       : $GSA_EMAIL"
echo

# ==============================
# Action buffers
# ==============================
ACTIONS_MIN=""
ACTIONS_FULL=""

add_min()  { ACTIONS_MIN+="$1"$'\n'; }
add_full() { ACTIONS_FULL+="$1"$'\n'; }

# ==============================
# Always add FULL actions
# ==============================
add_full "kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
add_full "kubectl create sa $KSA -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
add_full "gcloud iam service-accounts create $GSA \
  --project $PROJECT \
  --display-name \"GKE Workload Identity - $GSA\" || true"
add_full "gcloud iam service-accounts add-iam-policy-binding $GSA_EMAIL \
  --project $PROJECT \
  --role roles/iam.workloadIdentityUser \
  --member \"serviceAccount:$PROJECT.svc.id.goog[$NAMESPACE/$KSA]\""
add_full "kubectl annotate sa $KSA -n $NAMESPACE \
  iam.gke.io/gcp-service-account=$GSA_EMAIL --overwrite"

# ==============================
# Checks → build MIN actions
# ==============================

# Namespace
if kubectl get ns "$NAMESPACE" &>/dev/null; then
  echo "✔ Namespace exists"
else
  echo "➕ Namespace missing"
  add_min "kubectl create namespace $NAMESPACE"
fi

# KSA
if kubectl get sa "$KSA" -n "$NAMESPACE" &>/dev/null; then
  echo "✔ KSA exists"
else
  echo "➕ KSA missing"
  add_min "kubectl create sa $KSA -n $NAMESPACE"
fi

# GSA
if gcloud iam service-accounts describe "$GSA_EMAIL" \
  --project "$PROJECT" &>/dev/null; then
  echo "✔ GSA exists"
else
  echo "➕ GSA missing"
  add_min "gcloud iam service-accounts create $GSA \
  --project $PROJECT \
  --display-name \"GKE Workload Identity - $GSA\""
fi

# IAM binding
if gcloud iam service-accounts get-iam-policy "$GSA_EMAIL" \
  --project "$PROJECT" \
  --format=json | grep -q "$NAMESPACE/$KSA"; then
  echo "✔ IAM binding exists"
else
  echo "➕ IAM binding missing"
  add_min "gcloud iam service-accounts add-iam-policy-binding $GSA_EMAIL \
  --project $PROJECT \
  --role roles/iam.workloadIdentityUser \
  --member \"serviceAccount:$PROJECT.svc.id.goog[$NAMESPACE/$KSA]\""
fi

# Annotation
if kubectl get sa "$KSA" -n "$NAMESPACE" \
  -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' \
  2>/dev/null | grep -q "$GSA_EMAIL"; then
  echo "✔ KSA annotation exists"
else
  echo "➕ KSA annotation missing"
  add_min "kubectl annotate sa $KSA -n $NAMESPACE \
  iam.gke.io/gcp-service-account=$GSA_EMAIL --overwrite"
fi

# ==============================
# Decision
# ==============================
echo
echo "======================================"
echo "📋 Planned Actions (MINIMAL)"
echo "======================================"
[[ -z "$ACTIONS_MIN" ]] && echo "✔ Nothing to change" || echo "$ACTIONS_MIN"

echo
echo "======================================"
echo "❌Make Sure you are in correct k8s context❌"
echo "======================================"
read -p "🚀 Proceed? (y=execute | n=create script | f=full-force script): " RUN

RUN_LOWER=$(echo "$RUN" | tr '[:upper:]' '[:lower:]')

if [[ "$RUN_LOWER" == "y" ]]; then
  echo "⚡ Executing minimal actions..."
  eval "$ACTIONS_MIN"
  echo "✅ Done"

elif [[ "$RUN_LOWER" == "n" ]]; then
  FILE="$NAMESPACE-apply-workload-identity.sh"
  printf "#!/usr/bin/env bash\nset -e\n\n%s" "$ACTIONS_MIN" > "$FILE"
  chmod +x "$FILE"
  echo "📝 Script created: $FILE"

elif [[ "$RUN_LOWER" == "f" ]]; then
  FILE="$NAMESPACE-apply-workload-identity-FULL.sh"
  printf "#!/usr/bin/env bash\nset -e\n\n%s" "$ACTIONS_FULL" > "$FILE"
  chmod +x "$FILE"
  echo "📝 FULL script created: $FILE"

else
  echo "ℹ️ Exiting without changes"
fi

