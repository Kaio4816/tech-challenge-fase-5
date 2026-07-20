variable "region" {
  description = "Região AWS onde o bucket de state é criado."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Nome do bucket S3 de state. Se vazio, usa solidarytech-tfstate-<account_id>."
  type        = string
  default     = null
}
