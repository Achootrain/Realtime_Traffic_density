#!/bin/bash
# ============================================
# deploy.sh — Runs ON the EC2 instance
# Deploys K8s services via kubectl/helm.
#
# Usage: bash deploy.sh <changed_services>
#   changed_services: comma-separated list or "all"
#
# Env vars (injected by CI before bundling):
#   GHCR_USERNAME, GHCR_TOKEN
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# ============================================
set -e
export KUBECONFIG=/home/ubuntu/.kube/config
export HOME=/home/ubuntu

CHANGED_SERVICES="${1:-all}"
echo ">>> Services to restart: $CHANGED_SERVICES"

cd /home/ubuntu/k8s

# ---- Resolve EC2 public IP for Kafka (IMDSv2) ----
IMDS_TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)
EC2_HOST=$(curl -sf -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4 || echo "127.0.0.1")
sed -i "s/IP_PLACEHOLDER/$EC2_HOST/g" kafka.yaml || true

# ---- Setup Helm ----
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ---- Helm repos from services.json ----
CONFIG="/home/ubuntu/services.json"
if [ -f "$CONFIG" ]; then
  jq -r '.helm_repos | to_entries[] | "\(.key)=\(.value)"' "$CONFIG" | while IFS= read -r repo; do
    REPO_NAME="${repo%%=*}"
    REPO_URL="${repo#*=}"
    helm repo add "$REPO_NAME" "$REPO_URL" || true
  done
  helm repo update
fi

# ---- Create namespace ----
kubectl create namespace traffic --dry-run=client -o yaml | kubectl apply -f -

# ---- Create secrets ----
if [ -f /home/ubuntu/.deploy-secrets ]; then
  source /home/ubuntu/.deploy-secrets
fi

kubectl create secret docker-registry ghcr-secret \
  --namespace traffic \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USERNAME}" \
  --docker-password="${GHCR_TOKEN}" \
  --docker-email="noreply@example.com" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic aws-credentials \
  --namespace traffic \
  --from-literal=access_key_id="${AWS_ACCESS_KEY_ID}" \
  --from-literal=secret_access_key="${AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ---- Helm releases from services.json ----
if [ -f "$CONFIG" ]; then
  jq -c '.helm_releases[]' "$CONFIG" | while IFS= read -r release; do
    REL_NAME=$(echo "$release" | jq -r '.name')
    REL_CHART=$(echo "$release" | jq -r '.chart')
    SET_FLAGS=$(echo "$release" | jq -r '.set | to_entries[] | "--set \(.key)=\(.value)"' | tr '\n' ' ')
    echo ">>> Installing Helm release: $REL_NAME"
    helm upgrade --install "$REL_NAME" "$REL_CHART" --namespace traffic $SET_FLAGS
  done
fi

# ---- Apply all manifests via Kustomize ----
kubectl apply -k .

# ---- Post-deploy: TimescaleDB init ----
kubectl wait --for=condition=ready pod/timescaledb-0 -n traffic --timeout=120s || true
if [ -f /home/ubuntu/timescaledb/init.sql ]; then
  kubectl cp /home/ubuntu/timescaledb/init.sql traffic/timescaledb-0:/tmp/init.sql
  kubectl exec timescaledb-0 -n traffic -- psql -U postgres -d traffic -f /tmp/init.sql || true
fi

# ---- Restart changed services (data-driven) ----
if [ -f "$CONFIG" ]; then
  jq -c '.services[]' "$CONFIG" | while IFS= read -r svc; do
    SVC_NAME=$(echo "$svc" | jq -r '.name')

    if [[ "$CHANGED_SERVICES" == "all" ]] || echo "$CHANGED_SERVICES" | grep -qw "$SVC_NAME"; then
      echo ">>> Restarting service: $SVC_NAME"
      echo "$svc" | jq -r '.restart[]' | while IFS= read -r cmd; do
        echo "    Running: $cmd"
        eval "$cmd" || true
      done
    fi
  done
fi

echo ">>> Deploy complete!"
