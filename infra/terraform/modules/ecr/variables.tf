variable "repository_names" {
  type = list(string)
}

variable "max_images_per_repo" {
  type    = number
  default = 5
}

variable "enable_replication" {
  description = "Replica todos os repositórios da conta para replication_destination_region (usado pelo DR — o cluster em outra região puxa as imagens localmente)."
  type        = bool
  default     = false
}

variable "replication_destination_region" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
