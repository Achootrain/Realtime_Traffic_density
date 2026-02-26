output "public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.k3s.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.k3s.id
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.k3s.private_ip
}
