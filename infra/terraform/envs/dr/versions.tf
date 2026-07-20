# Este ambiente é a "modularização do warm standby": reusa exatamente os
# mesmos módulos do envs/primary, só que apontados para outra região e
# restaurando o Postgres de um snapshot. NÃO é aplicado no dia a dia — só
# sob demanda, pelo scripts/activate-dr.sh (Fase 6). State isolado do
# primary (key diferente no mesmo bucket), para que um `terraform destroy`
# aqui nunca encoste no ambiente principal.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key          = "dr/terraform.tfstate"
    use_lockfile = true
  }
}
