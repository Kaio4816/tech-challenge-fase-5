output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster, usado pelo módulo irsa para as roles das aplicações."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "node_security_group_id" {
  description = "Security group compartilhado dos nós — usado para liberar acesso ao RDS."
  value       = module.eks.node_security_group_id
}
