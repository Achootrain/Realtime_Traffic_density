# ===========================================
# Traffic System — Root Module
# ===========================================
# Deployment order:
#   1. Network (VPC, subnet, security group)
#   2. IAM (service user + keys)
#   3. Storage (S3 bucket)
#   4. Analytics (Glue + Athena)
#   5. Compute (EC2 + K3s)
#   6. K3s Apps (K8s workloads deployed via SSH)
# ===========================================

# -------------------------------------------
# Module 1: Networking
# -------------------------------------------
module "network" {
  source = "./modules/network"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  allowed_ssh_cidrs  = var.allowed_ssh_cidrs
}

# -------------------------------------------
# Module 2: IAM
# -------------------------------------------
module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  s3_bucket_name = var.s3_bucket_name
}

# -------------------------------------------
# Module 3: Storage (S3)
# -------------------------------------------
module "storage" {
  source = "./modules/storage"

  project_name            = var.project_name
  s3_bucket_name          = var.s3_bucket_name
  glacier_transition_days = var.glacier_transition_days
}

# -------------------------------------------
# Module 4: Analytics (Athena + Glue)
# -------------------------------------------
module "analytics" {
  source = "./modules/analytics"

  project_name   = var.project_name
  s3_bucket_name = module.storage.bucket_name
}

# -------------------------------------------
# Module 5: Compute (EC2 + K3s)
# -------------------------------------------
module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  environment          = var.environment
  instance_type        = var.instance_type
  root_volume_size     = var.root_volume_size
  ssh_public_key_path  = var.ssh_public_key_path
  ssh_private_key_path = var.ssh_private_key_path
  subnet_id            = module.network.public_subnet_id
  security_group_id    = module.network.security_group_id
}

# -------------------------------------------
# Module 6: K3s Applications
# -------------------------------------------
module "k3s_apps" {
  source = "./modules/k3s_apps"

  ec2_public_ip        = module.compute.public_ip
  ssh_private_key_path = var.ssh_private_key_path
  ec2_instance_id      = module.compute.instance_id

  # AWS credentials (from IAM module)
  aws_access_key_id     = module.iam.access_key_id
  aws_secret_access_key = module.iam.secret_access_key

  # GHCR credentials
  ghcr_username = var.ghcr_username
  ghcr_token    = var.ghcr_token

  # Application config
  grafana_admin_password = var.grafana_admin_password
  s3_bucket_name         = module.storage.bucket_name

  # Path to existing K8s manifests
  k8s_manifests_path = "${path.root}/../k8s"
  init_sql_path      = "${path.root}/../timescaledb/init.sql"
  clean_sh_path      = "${path.root}/../clean.sh"

  depends_on = [module.compute]
}
