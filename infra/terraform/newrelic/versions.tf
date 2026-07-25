terraform {
  required_version = ">= 1.9.0"

  required_providers {
    newrelic = {
      source  = "newrelic/newrelic"
      version = "~> 3.95"
    }
  }

  # Mesmo bucket de state do bootstrap, key isolada (o mesmo padrão de
  # envs/primary e envs/dr): valores reais vêm de backend.hcl na hora do
  # `terraform init -backend-config=backend.hcl`.
  backend "s3" {
    key          = "newrelic/terraform.tfstate"
    use_lockfile = true
  }
}
