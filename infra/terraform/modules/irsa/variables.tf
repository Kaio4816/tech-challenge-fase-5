variable "name_prefix" {
  type = string
}

variable "namespace" {
  description = "Namespace Kubernetes onde os Service Accounts das aplicações rodam (definido pelos manifests da Fase 4)."
  type        = string
  default     = "solidarytech"
}

variable "eks_oidc_provider_arn" {
  type = string
}

variable "eks_oidc_provider_url" {
  description = "URL do OIDC issuer do cluster, sem o https:// (ex.: oidc.eks.us-east-1.amazonaws.com/id/XXXX)."
  type        = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "dynamodb_table_arn" {
  type = string
}

variable "create_github_actions_role" {
  description = "O env dr não precisa de role de CI própria (o push sempre vai para o ECR do primary, que replica); deixe false lá."
  type        = bool
  default     = true
}

variable "create_github_oidc_provider" {
  description = "false se a conta AWS já tiver um OIDC provider para token.actions.githubusercontent.com (é um recurso único por conta — só o primary deve criar)."
  type        = bool
  default     = true
}

variable "github_org" {
  description = "Organização/usuário do GitHub dono do repositório (para a trust policy da role de CI). Só usado quando create_github_actions_role = true."
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "Nome do repositório GitHub (para a trust policy da role de CI). Placeholder até o repo existir — ver CLAUDE.md. Só usado quando create_github_actions_role = true."
  type        = string
  default     = ""
}

variable "ecr_repository_arns" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
