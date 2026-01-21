#!/bin/bash
set -e

############################################
# IAM ROLE REPLICATOR FOR GCP PROJECTS
#
# Replicates IAM roles from one principal
# to another principal or project.
#
# Supports:
# - user:
# - group:
# - serviceAccount:
#
# Features:
# - --dry-run (no changes)
# - --help (usage guide)
# - Save commands to script OR execute now
############################################

SCRIPT_NAME=$(basename "$0")

############################################
# HELP
############################################
show_help() {
cat <<EOF
NAME
  $SCRIPT_NAME - GCP IAM Role Replicator

DESCRIPTION
  Replicates IAM roles assigned to a principal
  from a source project to:
    1) Another principal in the SAME project
    2) The SAME principal in ANOTHER project

USAGE
  $SCRIPT_NAME [OPTIONS] <SOURCE_PROJECT> <SOURCE_PRINCIPAL>

OPTIONS
  --dry-run
      Show what commands would be executed.
      No IAM changes are made.

  --help
      Show this help message and exit.

ARGUMENTS
  SOURCE_PROJECT
      GCP project ID where roles are read from.

  SOURCE_PRINCIPAL
      IAM principal whose roles will be replicated.
      Formats:
        user:email
        group:email
        serviceAccount:email

EXAMPLES
  Replicate roles from a user:
    $SCRIPT_NAME my-project user:john@example.com

  Dry run:
    $SCRIPT_NAME --dry-run my-project group:devops@example.com

REQUIRED PERMISSIONS
  On source project:
    roles/viewer

  On target project:
    roles/resourcemanager.projectIamAdmin

NOTES
  - Project-level IAM only
  - Conditional bindings are NOT replicated
  - Safe to re-run (idempotent)
EOF
}

############################################
# ARG PARSING
############################################
DRY_RUN=false
ARGS=()

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

if [[ ${#ARGS[@]} -ne 2 ]]; then
  echo "❌ Invalid arguments"
  echo
  show_help
  exit 1
fi

SOURCE_PROJECT="${ARGS[0]}"
SOURCE_PRINCIPAL="${ARGS[1]}"

############################################
# FETCH ROLES
############################################
echo "🔍 Fetching IAM roles"
echo "   Project   : $SOURCE_PROJECT"
echo "   Principal : $SOURCE_PRINCIPAL"
echo

ROLES=$(gcloud projects get-iam-policy "$SOURCE_PROJECT" \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SOURCE_PRINCIPAL" \
  --format="value(bindings.role)")

if [[ -z "$ROLES" ]]; then
  echo "❌ No roles found"
  exit 1
fi

echo "✅ Roles found:"
echo "$ROLES"
echo

############################################
# REPLICATION MODE
############################################
echo "Choose replication option:"
echo "1) Replicate to another principal (same project)"
echo "2) Replicate to same principal (another project)"
read -rp "Enter choice [1/2]: " MODE

case "$MODE" in
  1)
    read -rp "Enter TARGET principal (user:/group:/serviceAccount:): " TARGET_PRINCIPAL
    TARGET_PROJECT="$SOURCE_PROJECT"
    ;;
  2)
    TARGET_PRINCIPAL="$SOURCE_PRINCIPAL"
    read -rp "Enter TARGET project ID: " TARGET_PROJECT
    ;;
  *)
    echo "❌ Invalid option"
    exit 1
    ;;
esac

############################################
# EXECUTION MODE
############################################
echo
echo "Choose execution mode:"
echo "1) Run commands now"
echo "2) Save commands to script and exit"
read -rp "Enter choice [1/2]: " EXEC_MODE

CMD_FILE="apply-iam-$(date +%Y%m%d-%H%M%S).sh"

if [[ "$EXEC_MODE" == "2" ]]; then
  echo "#!/bin/bash" > "$CMD_FILE"
  echo "set -e" >> "$CMD_FILE"
  echo >> "$CMD_FILE"
fi

############################################
# APPLY / SAVE COMMANDS
############################################
echo
echo "🚀 Processing roles..."
echo

for ROLE in $ROLES; do
  CMD="gcloud projects add-iam-policy-binding \"$TARGET_PROJECT\" \
    --member=\"$TARGET_PRINCIPAL\" \
    --role=\"$ROLE\" \
    --quiet"

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] $CMD"
    continue
  fi

  if [[ "$EXEC_MODE" == "1" ]]; then
    echo "▶ Applying $ROLE"
    eval "$CMD"
  else
    echo "$CMD" >> "$CMD_FILE"
  fi
done

############################################
# FINALIZE
############################################
if [[ "$DRY_RUN" == true ]]; then
  echo
  echo "✅ Dry run completed. No changes were made."
  exit 0
fi

if [[ "$EXEC_MODE" == "2" ]]; then
  chmod +x "$CMD_FILE"
  echo
  echo "✅ Commands saved to: $CMD_FILE"
  echo "▶ Review and execute when ready:"
  echo "   ./$CMD_FILE"
  exit 0
fi

echo
echo "✅ IAM role replication completed successfully"

