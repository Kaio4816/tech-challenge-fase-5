variable "table_name" {
  type    = string
  default = "SolidaryTechVolunteers"
}

variable "replica_regions" {
  description = "Regiões de réplica (Global Table). Vazio = tabela regional simples. Streams são ativados automaticamente quando há réplicas (exigência do Global Tables v2)."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
