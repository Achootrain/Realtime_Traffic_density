# ===========================================
# Traffic System — Root Module (Infrastructure Only)
# ===========================================
# Terraform provisions infrastructure. K8s app
# deployment is handled by GitHub Actions CI/CD.
#
# Modules:
#   1. Network  (VPC, subnet, security group)
#   2. IAM      (service user + keys)
#   3. Storage  (S3 bucket)
#   4. Analytics(Glue + Athena)
#   5. Compute  (EC2 + K3s bootstrap)
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
  ssh_public_key       = var.ssh_public_key
  ssh_private_key      = var.ssh_private_key
  subnet_id            = module.network.public_subnet_id
  security_group_id    = module.network.security_group_id
}
