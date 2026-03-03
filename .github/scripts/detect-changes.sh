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

# ---- Fix line endings & BOM in services.json ----
sed -i 's/\r$//' services.json
sed -i '1s/^\xef\xbb\xbf//' services.json

# Debug: show file info
echo ">>> services.json encoding:"
file services.json
echo ">>> First 100 bytes (hex):"
xxd -l 100 services.json || od -A x -t x1z -N 100 services.json
echo ">>> Validating JSON..."
jq empty services.json && echo ">>> JSON is valid" || { echo ">>> JSON is INVALID"; cat services.json; exit 1; }

# Auto-detect from git diff
CHANGED_FILES=$(git diff --name-only HEAD^ HEAD 2>/dev/null || echo "")
CHANGED_SERVICES=""

# Read each service's source_dir from services.json
for row in $(jq -c '.services[]' services.json); do
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
