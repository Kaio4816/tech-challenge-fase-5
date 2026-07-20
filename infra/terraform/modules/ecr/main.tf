resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  # A infra é efêmera por design (custo mínimo, apply/destroy a cada demo) —
  # sem isso, um repositório com qualquer imagem publicada trava o
  # `terraform destroy` (a AWS recusa apagar repo ECR não-vazio).
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Manter apenas as ${var.max_images_per_repo} imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.max_images_per_repo
      }
      action = { type = "expire" }
    }]
  })
}

# Replicação cross-region: é uma configuração única por conta/registry, por
# isso só o env primary deve habilitar (enable_replication = true). O env dr
# não cria repositórios próprios — consome a réplica que a AWS mantém
# automaticamente em replication_destination_region.
resource "aws_ecr_replication_configuration" "this" {
  count = var.enable_replication ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = var.replication_destination_region
        registry_id = data.aws_caller_identity.current[0].account_id
      }
    }
  }
}

data "aws_caller_identity" "current" {
  count = var.enable_replication ? 1 : 0
}
