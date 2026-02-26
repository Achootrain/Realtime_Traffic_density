variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name"
  type        = string
}

variable "glacier_transition_days" {
  description = "Days before transitioning to Glacier"
  type        = number
}
