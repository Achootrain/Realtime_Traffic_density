variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for IAM policy"
  type        = string
}

variable "tfstate_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "traffic-system-tfstate"
}
