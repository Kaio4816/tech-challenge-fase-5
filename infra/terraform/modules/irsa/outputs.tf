output "donation_service_role_arn" {
  value = aws_iam_role.donation_service.arn
}

output "volunteer_service_role_arn" {
  value = aws_iam_role.volunteer_service.arn
}

output "github_actions_role_arn" {
  description = "Configurar como vars.AWS_ECR_ROLE_ARN no repositório GitHub (habilita o job \"push\" dos workflows de CI). Null quando create_github_actions_role = false (env dr)."
  value       = var.create_github_actions_role ? aws_iam_role.github_actions[0].arn : null
}
