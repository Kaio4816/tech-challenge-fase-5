terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
  }

  # Backend parcial: valores reais (bucket/key/region) vêm de
  # backend.hcl na hora do `terraform init -backend-config=backend.hcl`
  # (backend.hcl é gerado localmente a partir de backend.hcl.example e não
  # é versionado — ver README). use_lockfile ativa o lock nativo do S3
  # (Terraform >= 1.10), sem precisar de tabela DynamoDB.
  backend "s3" {
    key          = "primary/terraform.tfstate"
    use_lockfile = true
  }
}
