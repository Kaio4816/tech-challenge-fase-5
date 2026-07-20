variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets (privadas) para o DB subnet group."
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group dos nós EKS — liberado na porta 5432."
  type        = string
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "engine_version" {
  description = "Major version do Postgres (a AWS resolve a minor mais recente)."
  type        = string
  default     = "16"
}

variable "master_username" {
  type    = string
  default = "solidarytech"
}

variable "backup_retention_period" {
  type    = number
  default = 1
}

variable "snapshot_identifier" {
  description = "Se definido, a instância é restaurada a partir deste snapshot (warm standby / DR) em vez de nascer vazia."
  type        = string
  default     = null
}

variable "publicly_accessible" {
  description = <<-EOT
    Só deve ser true no ambiente primary: é o que permite ao Terraform
    (rodando localmente, fora da VPC) criar os databases ngo_db/donation_db
    via provider postgresql. O acesso continua restrito por security group
    (admin_cidr_blocks + SG dos nós EKS), não fica aberto ao mundo.
  EOT
  type        = bool
  default     = false
}

variable "admin_cidr_blocks" {
  description = "CIDRs extras liberados na porta 5432 (ex.: IP de quem roda o terraform apply). Vazio em condições normais."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
