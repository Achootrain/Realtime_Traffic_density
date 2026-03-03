#!/bin/bash
# ============================================
# ssm-deploy.sh — Upload bundle & execute on EC2 via SSM
#
# Usage: bash ssm-deploy.sh <ec2_id> <changed_services>
# ============================================
set -e

EC2_ID="${1:?EC2 instance ID required}"
CHANGED="${2:-all}"

echo ">>> Deploying to EC2: $EC2_ID"
echo ">>> Services: $CHANGED"

# ---- Build the bundle ----
tar czf /tmp/deploy-bundle.tar.gz \
  k8s/*.yaml \
  timescaledb/init.sql \
  clean.sh \
  services.json \
  scripts/deploy.sh \
  -C /tmp .deploy-secrets 2>/dev/null || \
tar czf /tmp/deploy-bundle.tar.gz \
  k8s/*.yaml \
  timescaledb/init.sql \
  clean.sh \
  services.json \
  scripts/deploy.sh

BUNDLE_SIZE=$(stat -c%s /tmp/deploy-bundle.tar.gz)
echo ">>> Bundle size: $BUNDLE_SIZE bytes"

# ---- Upload via SSM ----
if [ "$BUNDLE_SIZE" -gt 20000 ]; then
  echo ">>> Bundle too large for inline SSM, uploading to S3..."
  BUCKET="${S3_BUCKET_NAME:-traffic-count-bigdata}"
  aws s3 cp /tmp/deploy-bundle.tar.gz "s3://${BUCKET}/deploy/deploy-bundle.tar.gz"
  COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$EC2_ID" \
    --document-name "AWS-RunShellScript" \
    --timeout-seconds 60 \
    --parameters commands='[
      "mkdir -p /home/ubuntu/k8s /home/ubuntu/timescaledb /home/ubuntu/scripts",
      "aws s3 cp s3://'"${BUCKET}"'/deploy/deploy-bundle.tar.gz /tmp/deploy-bundle.tar.gz",
      "cd /home/ubuntu && tar xzf /tmp/deploy-bundle.tar.gz",
      "chmod +x /home/ubuntu/clean.sh /home/ubuntu/scripts/deploy.sh",
      "rm -f /tmp/deploy-bundle.tar.gz"
    ]' \
    --query "Command.CommandId" --output text)
else
  BUNDLE_B64=$(base64 -w0 /tmp/deploy-bundle.tar.gz)
  COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$EC2_ID" \
    --document-name "AWS-RunShellScript" \
    --timeout-seconds 60 \
    --parameters commands="[
      \"mkdir -p /home/ubuntu/k8s /home/ubuntu/timescaledb /home/ubuntu/scripts\",
      \"echo '${BUNDLE_B64}' | base64 -d > /tmp/deploy-bundle.tar.gz\",
      \"cd /home/ubuntu && tar xzf /tmp/deploy-bundle.tar.gz\",
      \"chmod +x /home/ubuntu/clean.sh /home/ubuntu/scripts/deploy.sh\",
      \"rm -f /tmp/deploy-bundle.tar.gz\"
    ]" \
    --query "Command.CommandId" --output text)
fi

aws ssm wait command-executed \
  --command-id "$COMMAND_ID" \
  --instance-id "$EC2_ID" || true

STATUS=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$EC2_ID" \
  --query "Status" --output text)

if [[ "$STATUS" != "Success" ]]; then
  echo ">>> Upload failed with status: $STATUS"
  aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$EC2_ID" \
    --query "StandardErrorContent" --output text
  exit 1
fi
echo ">>> Bundle uploaded successfully"

# ---- Execute deploy script via SSM ----
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$EC2_ID" \
  --document-name "AWS-RunShellScript" \
  --timeout-seconds 300 \
  --parameters commands='["bash /home/ubuntu/scripts/deploy.sh '"$CHANGED"'"]' \
  --query "Command.CommandId" --output text)

echo ">>> SSM Command ID: $COMMAND_ID"
echo ">>> Waiting for deployment to complete..."

aws ssm wait command-executed \
  --command-id "$COMMAND_ID" \
  --instance-id "$EC2_ID" || true

RESULT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$EC2_ID")

STATUS=$(echo "$RESULT" | jq -r '.Status')
echo ">>> Command Status: $STATUS"
echo "--- STDOUT ---"
echo "$RESULT" | jq -r '.StandardOutputContent'
echo "--- STDERR ---"
echo "$RESULT" | jq -r '.StandardErrorContent'

if [[ "$STATUS" != "Success" ]]; then
  echo ">>> Deployment failed!"
  exit 1
fi

echo ">>> Deployment successful!"
