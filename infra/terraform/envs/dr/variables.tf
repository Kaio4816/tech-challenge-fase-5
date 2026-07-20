variable "region" {
  type    = string
  default = "us-east-2"
}

variable "name_prefix" {
  type    = string
  default = "solidarytech-dr"
}

variable "snapshot_identifier" {
  description = "ARN/identifier do snapshot do RDS (copiado de us-east-1 para esta região) a partir do qual o Postgres é restaurado. Obrigatório — sem ele o warm standby não tem dados. Preenchido pelo scripts/activate-dr.sh."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Nome da tabela cuja réplica (Global Table) já existe nesta região, criada pelo envs/primary."
  type        = string
  default     = "SolidaryTechVolunteers"
}

variable "tags" {
  type = map(string)
  default = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
  }
}
