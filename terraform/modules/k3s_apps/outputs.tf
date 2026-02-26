output "deploy_status" {
  description = "K3s apps deployment resource ID"
  value       = null_resource.deploy_k8s.id
}
