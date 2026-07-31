provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

# IP público de quem roda o `terraform apply`, liberado no security group do
# RDS só para permitir a criação dos databases ngo_db/donation_db (ver
# provider "postgresql" abaixo e módulo rds-postgres). Em uma operação real
# isso rodaria de dentro da VPC (bastion/SSM/CI runner); aqui é o trade-off
# trade-off custo/simplicidade assumido neste projeto.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  admin_cidr = "${chomp(data.http.my_ip.response_body)}/32"
}

# Configuração depende de module.rds (endpoint só existe após a instância
# ser criada) — é o padrão documentado do Terraform para provedores cuja
# configuração só fica disponível depois de outro recurso existir: a
# primeira aplicação cria o RDS, a segunda cria os databases.
provider "postgresql" {
  host      = module.rds.address
  port      = module.rds.port
  username  = module.rds.master_username
  password  = module.rds.master_password
  sslmode   = "require"
  superuser = false

  connect_timeout = 15
}
