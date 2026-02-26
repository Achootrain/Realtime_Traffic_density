# ===========================================
# Outputs
# ===========================================

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance running K3s"
  value       = module.compute.public_ip
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = module.compute.instance_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "s3_bucket_name" {
  description = "S3 bucket name for traffic data"
  value       = module.storage.bucket_name
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.storage.bucket_arn
}

output "iam_access_key_id" {
  description = "IAM access key ID for the service user"
  value       = module.iam.access_key_id
  sensitive   = true
}

output "grafana_url" {
  description = "Grafana URL (NodePort 3000)"
  value       = "http://${module.compute.public_ip}:3000"
}

output "ssh_command" {
  description = "SSH command to connect to EC2"
  value       = "ssh -i <your-private-key> ubuntu@${module.compute.public_ip}"
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = module.analytics.workgroup_name
}

output "glue_database" {
  description = "Glue catalog database name"
  value       = module.analytics.database_name
}
