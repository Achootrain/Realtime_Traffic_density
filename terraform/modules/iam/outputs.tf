output "access_key_id" {
  description = "IAM access key ID"
  value       = aws_iam_access_key.service.id
  sensitive   = true
}

output "secret_access_key" {
  description = "IAM secret access key"
  value       = aws_iam_access_key.service.secret
  sensitive   = true
}

output "iam_user_name" {
  description = "IAM user name"
  value       = aws_iam_user.service.name
}

output "iam_user_arn" {
  description = "IAM user ARN"
  value       = aws_iam_user.service.arn
}
