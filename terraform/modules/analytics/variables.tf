variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for data and Athena results"
  type        = string
}
