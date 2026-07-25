output "cluster_name" {
  value = module.eks.cluster_name
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
  value = data.aws_dynamodb_table.volunteers.name
}

output "donation_service_role_arn" {
  value = module.irsa.donation_service_role_arn
}

output "volunteer_service_role_arn" {
  value = module.irsa.volunteer_service_role_arn
}
