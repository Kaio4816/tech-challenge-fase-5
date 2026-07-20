locals {
  cluster_name = "${var.name_prefix}-eks"
}

module "network" {
  source = "../../modules/network"

  name_prefix  = var.name_prefix
  region       = var.region
  cluster_name = local.cluster_name
  tags         = var.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  tags               = var.tags
}

module "rds" {
  source = "../../modules/rds-postgres"

  name_prefix                = var.name_prefix
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  # Restaura de snapshot: username/senha/databases (ngo_db/donation_db) já
  # vêm prontos, nenhum provider postgresql é necessário aqui.
  snapshot_identifier = var.snapshot_identifier
  publicly_accessible = false

  tags = var.tags
}

# Fila recriada do zero: eventos de notificação, não são dados
# transacionais — perda aceitável em um failover (documentado em
# docs/dr-plan.md na Fase 6).
module "sqs" {
  source = "../../modules/sqs"

  name_prefix = var.name_prefix
  tags        = var.tags
}

# A tabela em si (e sua réplica Global Table nesta região) já existe — foi
# criada pelo envs/primary. O DR só referencia, nunca cria.
data "aws_dynamodb_table" "volunteers" {
  name = var.dynamodb_table_name
}

module "irsa" {
  source = "../../modules/irsa"

  name_prefix = var.name_prefix

  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_oidc_provider_url = module.eks.oidc_provider_url

  sqs_queue_arn      = module.sqs.queue_arn
  dynamodb_table_arn = data.aws_dynamodb_table.volunteers.arn

  # O push de imagens sempre acontece no ECR do primary (que replica para cá
  # automaticamente); o DR não precisa da sua própria role/OIDC provider de CI.
  create_github_actions_role = false

  tags = var.tags
}
