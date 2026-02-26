variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
}

variable "ssh_public_key_path" {
  description = "Local path to SSH public key"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Local path to SSH private key"
  type        = string
  sensitive   = true
}

variable "subnet_id" {
  description = "Subnet ID to launch EC2 into"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for EC2"
  type        = string
}
