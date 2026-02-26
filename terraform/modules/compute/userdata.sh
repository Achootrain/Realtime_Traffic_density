#!/bin/bash
set -e

# ===========================================
# K3s Installation Script (EC2 User-Data)
# ===========================================

# Update system
apt-get update -y
apt-get upgrade -y

# Install prerequisites
apt-get install -y \
  curl \
  apt-transport-https \
  ca-certificates \
  software-properties-common \
  jq \
  unzip

# Install K3s (single-node, no traefik to save resources)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable=traefik \
  --write-kubeconfig-mode=644 \
  --tls-san=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)" \
  sh -

# Wait for K3s to be ready
echo "Waiting for K3s to be ready..."
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 5
done
echo "K3s is ready!"

# Configure kubectl for ubuntu user
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config

# Set KUBECONFIG in ubuntu user profile
echo 'export KUBECONFIG=~/.kube/config' >> /home/ubuntu/.bashrc

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "K3s + Helm installation complete!"
