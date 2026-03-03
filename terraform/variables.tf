# ===========================================
# General
# ===========================================
# AWS credentials are provided via environment variables:
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "traffic-system"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# ===========================================
# Compute (EC2 + K3s)
# ===========================================
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m7i-flex.large"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 40
}

variable "ssh_public_key" {
  description = "SSH public key content for EC2 key pair"
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key content (for provisioners)"
  type        = string
  sensitive   = true
}

# ===========================================
# Networking
# ===========================================
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH into EC2"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ===========================================
# Storage (S3)
# ===========================================
variable "s3_bucket_name" {
  description = "S3 bucket name for traffic data"
  type        = string
  default     = "traffic-count-bigdata"
}

variable "glacier_transition_days" {
  description = "Days before S3 objects transition to Glacier"
  type        = number
  default     = 30
}
