# ===========================================
# K3s Apps — Variables
# ===========================================

variable "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Local path to SSH private key"
  type        = string
  sensitive   = true
}

variable "ec2_instance_id" {
  description = "EC2 instance ID (used as trigger for re-deployment)"
  type        = string
}

# AWS credentials
variable "aws_access_key_id" {
  description = "AWS access key ID for K8s secret"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key for K8s secret"
  type        = string
  sensitive   = true
}

# GHCR credentials
variable "ghcr_username" {
  description = "GitHub Container Registry username"
  type        = string
}

variable "ghcr_token" {
  description = "GitHub Container Registry token"
  type        = string
  sensitive   = true
}

# Application config
variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "S3 bucket name"
  type        = string
}

# Paths to existing manifests
variable "k8s_manifests_path" {
  description = "Local path to k8s/ directory containing YAML manifests"
  type        = string
}

variable "init_sql_path" {
  description = "Local path to timescaledb/init.sql"
  type        = string
}

variable "clean_sh_path" {
  description = "Local path to clean.sh script"
  type        = string
}
