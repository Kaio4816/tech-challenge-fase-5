variable "region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  description = "Região de destino da replicação ECR / Global Table DynamoDB (deve casar com envs/dr)."
  type        = string
  default     = "us-east-2"
}

variable "name_prefix" {
  type    = string
  default = "solidarytech-primary"
}

variable "github_org" {
  description = "Dono (usuário/organização) do repositório GitHub, usado na trust policy OIDC do GitHub Actions."
  type        = string
}

variable "github_repo" {
  description = "Nome do repositório GitHub, usado na trust policy OIDC do GitHub Actions."
  type        = string
}

variable "tags" {
  type = map(string)
  default = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
  }
}
