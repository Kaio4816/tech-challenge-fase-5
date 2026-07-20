variable "name_prefix" {
  description = "Prefixo dos nomes dos recursos (ex.: solidarytech-primary)."
  type        = string
}

variable "region" {
  description = "Região AWS onde a rede é criada."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Quantidade de AZs a usar (custo mínimo: 2)."
  type        = number
  default     = 2
}

variable "cluster_name" {
  description = "Nome do cluster EKS que vai usar esta rede (para as tags kubernetes.io/cluster/<name>)."
  type        = string
}

variable "tags" {
  description = "Tags FinOps aplicadas a todos os recursos (Project/Environment/CostCenter)."
  type        = map(string)
  default     = {}
}
