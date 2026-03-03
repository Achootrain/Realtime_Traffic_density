#!/bin/bash
# ============================================
# detect-changes.sh
# Detects which services changed based on git diff
# and services.json registry.
#
# Usage: bash detect-changes.sh [manual_service]
# Output: writes "services=..." to $GITHUB_OUTPUT
# ============================================
set -e

MANUAL_SERVICE="${1:-}"

if [[ -n "$MANUAL_SERVICE" ]]; then
  echo "services=$MANUAL_SERVICE" >> "$GITHUB_OUTPUT"
  echo ">>> Manual target: $MANUAL_SERVICE"
  exit 0
fi

# Auto-detect from git diff
CHANGED_FILES=$(git diff --name-only HEAD^ HEAD 2>/dev/null || echo "")
CHANGED_SERVICES=""

# Read each service's source_dir from services.json
# NOTE: Use "while read" not "for" — jq output contains spaces
jq -c '.services[]' services.json | while IFS= read -r row; do
  SVC_NAME=$(echo "$row" | jq -r '.name')
  SRC_DIR=$(echo "$row" | jq -r '.source_dir')

  if echo "$CHANGED_FILES" | grep -q "^${SRC_DIR}"; then
    CHANGED_SERVICES="${CHANGED_SERVICES}${CHANGED_SERVICES:+,}${SVC_NAME}"
  fi
done

# If k8s/ manifests changed, deploy all
if echo "$CHANGED_FILES" | grep -q "^k8s/"; then
  CHANGED_SERVICES="all"
fi

# Default: deploy all if nothing specific detected
if [[ -z "$CHANGED_SERVICES" ]]; then
  CHANGED_SERVICES="all"
fi

echo "services=$CHANGED_SERVICES" >> "$GITHUB_OUTPUT"
echo ">>> Auto-detected: $CHANGED_SERVICES"
