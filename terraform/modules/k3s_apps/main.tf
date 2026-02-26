# ===========================================
# K3s Apps Module — Deploy K8s Workloads via SSH
# ===========================================
# This module copies K8s manifests to EC2 and applies them
# using kubectl/helm over SSH, matching the GitHub Actions workflow.
# ===========================================

locals {
  remote_base_dir      = "/home/ubuntu/traffic-deploy"
  remote_k8s_dir       = "${local.remote_base_dir}/k8s"
  remote_timescale_dir = "${local.remote_base_dir}/timescaledb"
}

# -------------------------------------------
# Step 1: Copy manifests to EC2
# -------------------------------------------
resource "null_resource" "copy_manifests" {
  triggers = {
    # Re-deploy when manifests change (hash of key files)
    instance_id = var.ec2_instance_id
    manifest_hash = sha256(join("", [
      filesha256("${var.k8s_manifests_path}/kustomization.yaml"),
      filesha256("${var.k8s_manifests_path}/kafka.yaml"),
      filesha256("${var.k8s_manifests_path}/producer-deployment.yaml"),
      filesha256("${var.k8s_manifests_path}/timescaledb.yaml"),
      filesha256("${var.k8s_manifests_path}/grafana.yaml"),
      filesha256("${var.k8s_manifests_path}/spark-realtime-app.yaml"),
      filesha256("${var.k8s_manifests_path}/spark-s3-glacier-app.yaml"),
      filesha256("${var.k8s_manifests_path}/spark-operator-complete-rbac.yaml"),
      filesha256("${var.k8s_manifests_path}/namespace.yaml"),
      filesha256(var.init_sql_path),
      filesha256(var.clean_sh_path),
    ]))
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = var.ec2_public_ip
    timeout     = "5m"
  }

  # Create directories
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${local.remote_k8s_dir}",
      "mkdir -p ${local.remote_timescale_dir}",
    ]
  }

  # Copy K8s manifests
  provisioner "file" {
    source      = "${var.k8s_manifests_path}/"
    destination = local.remote_k8s_dir
  }

  # Copy init.sql
  provisioner "file" {
    source      = var.init_sql_path
    destination = "${local.remote_timescale_dir}/init.sql"
  }

  # Copy clean.sh
  provisioner "file" {
    source      = var.clean_sh_path
    destination = "${local.remote_base_dir}/clean.sh"
  }

  # Make clean.sh executable
  provisioner "remote-exec" {
    inline = [
      "chmod +x ${local.remote_base_dir}/clean.sh",
    ]
  }
}

# -------------------------------------------
# Step 2: Configure & Deploy K8s workloads
# -------------------------------------------
resource "null_resource" "deploy_k8s" {
  depends_on = [null_resource.copy_manifests]

  triggers = {
    instance_id       = var.ec2_instance_id
    manifest_hash     = null_resource.copy_manifests.triggers.manifest_hash
    aws_key_hash      = sha256(var.aws_access_key_id)
    ghcr_hash         = sha256(var.ghcr_token)
    grafana_pass_hash = sha256(var.grafana_admin_password)
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = var.ec2_public_ip
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "export KUBECONFIG=~/.kube/config",

      # ----------------------------------------
      # A. Replace IP placeholder in kafka.yaml
      # ----------------------------------------
      "echo '>>> Patching Kafka advertised listeners...'",
      "sed -i 's/IP_PLACEHOLDER/${var.ec2_public_ip}/g' ${local.remote_k8s_dir}/kafka.yaml || true",

      # ----------------------------------------
      # B. Create namespace
      # ----------------------------------------
      "echo '>>> Creating namespace...'",
      "kubectl create namespace traffic --dry-run=client -o yaml | kubectl apply -f -",

      # ----------------------------------------
      # C. Create secrets
      # ----------------------------------------
      "echo '>>> Creating GHCR imagePullSecret...'",
      "kubectl create secret docker-registry ghcr-secret \\",
      "  --namespace traffic \\",
      "  --docker-server=ghcr.io \\",
      "  --docker-username='${var.ghcr_username}' \\",
      "  --docker-password='${var.ghcr_token}' \\",
      "  --docker-email='noreply@example.com' \\",
      "  --dry-run=client -o yaml | kubectl apply -f -",

      "echo '>>> Creating AWS credentials secret...'",
      "kubectl create secret generic aws-credentials \\",
      "  --namespace traffic \\",
      "  --from-literal=access_key_id='${var.aws_access_key_id}' \\",
      "  --from-literal=secret_access_key='${var.aws_secret_access_key}' \\",
      "  --dry-run=client -o yaml | kubectl apply -f -",

      # ----------------------------------------
      # D. Install/Upgrade Spark Operator via Helm
      # ----------------------------------------
      "echo '>>> Setting up Spark Operator...'",
      "helm repo add spark-operator https://kubeflow.github.io/spark-operator || true",
      "helm repo update",
      "helm upgrade --install spark-operator-1 spark-operator/spark-operator \\",
      "  --namespace traffic \\",
      "  --set controller.namespaces={traffic} \\",
      "  --set webhook.enable=true \\",
      "  --wait --timeout 300s",

      # ----------------------------------------
      # E. Apply all manifests via Kustomize
      # ----------------------------------------
      "echo '>>> Applying Kustomize manifests...'",
      "cd ${local.remote_k8s_dir}",
      "kubectl apply -k . || kubectl apply -k .",

      # ----------------------------------------
      # F. Initialize TimescaleDB
      # ----------------------------------------
      "echo '>>> Initializing TimescaleDB...'",
      "kubectl wait --for=condition=ready pod/timescaledb-0 -n traffic --timeout=180s || true",
      "kubectl cp ${local.remote_timescale_dir}/init.sql traffic/timescaledb-0:/tmp/init.sql",
      "kubectl exec timescaledb-0 -n traffic -- psql -U postgres -d traffic -f /tmp/init.sql || true",
      "echo '>>> TimescaleDB initialized'",

      # ----------------------------------------
      # G. Verify deployment
      # ----------------------------------------
      "echo '>>> Deployment status:'",
      "kubectl get all -n traffic",
      "echo '>>> Done!'",
    ]
  }
}
