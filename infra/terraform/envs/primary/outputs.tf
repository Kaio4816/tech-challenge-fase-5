output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "rds_master_username" {
  value = module.rds.master_username
}

output "rds_master_password" {
  value     = module.rds.master_password
  sensitive = true
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "donation_service_role_arn" {
  value = module.irsa.donation_service_role_arn
}

output "volunteer_service_role_arn" {
  value = module.irsa.volunteer_service_role_arn
}

output "github_actions_role_arn" {
  description = "Configurar em Settings > Secrets and variables > Actions > Variables como AWS_ECR_ROLE_ARN."
  value       = module.irsa.github_actions_role_arn
}
