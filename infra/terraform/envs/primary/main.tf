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

  # 4 nós (não 2) porque o limite real aqui é POD POR NÓ, não CPU/memória:
  # o AWS VPC CNI aloca IPs de pod por ENI, e uma t3.medium comporta
  # 3 ENIs x 6 IPs - 1 = 17 pods. Com a stack de observabilidade da F5
  # (kube-prometheus-stack + Loki + Promtail + nri-bundle) os 2 nós
  # originais bateram o teto com CPU em ~50% e memória em ~45%, e pods
  # ficaram Pending com "Too many pods" -- sintoma que engana, porque
  # `kubectl top` mostra o cluster folgado.
  #
  # Alternativa sem nós extras: ligar prefix delegation no addon vpc-cni
  # (ENABLE_PREFIX_DELEGATION=true), que leva o teto a ~110 pods/nó a
  # custo zero. Exige reciclar os nós para o kubelet recalcular --max-pods,
  # então fica registrado como otimização de FinOps, não aplicada no meio
  # da janela de verificação.
  node_desired_size = 4
  node_max_size     = 5
}

module "rds" {
  source = "../../modules/rds-postgres"

  name_prefix = var.name_prefix
  vpc_id      = module.network.vpc_id

  # Subnets PÚBLICAS de propósito: publicly_accessible = true não basta para
  # o Terraform (rodando localmente) alcançar a instância se ela estiver numa
  # subnet privada (a rota só existe via NAT, sem caminho de entrada da
  # internet). O tráfego dos nós EKS (subnets privadas) continua funcionando
  # normalmente pela rota "local" implícita da VPC entre subnets — só a
  # alcançabilidade externa depende de estar na subnet pública. Acesso segue
  # restrito pelo security group (só admin_cidr_blocks + SG dos nós).
  subnet_ids                 = module.network.public_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  # Só o primary precisa disso — é o que permite ao Terraform criar os
  # databases via provider postgresql (ver providers.tf).
  publicly_accessible = true
  admin_cidr_blocks   = [local.admin_cidr]

  tags = var.tags
}

resource "postgresql_database" "ngo" {
  name = "ngo_db"

  # Sem isso, um `terraform destroy` pode apagar as rotas/subnets públicas
  # de module.network antes de conseguir conectar para dar DROP DATABASE
  # (só existe dependência implícita via provider "postgresql" -> module.rds,
  # não -> module.network). Achado num destroy real: a rota pública foi
  # destruída primeiro, o provider deu timeout, e o RDS ficou preso segurando
  # o IGW (DependencyViolation). depends_on força a ordem reversa correta.
  depends_on = [module.network]
}

resource "postgresql_database" "donation" {
  name = "donation_db"

  depends_on = [module.network]
}

module "sqs" {
  source = "../../modules/sqs"

  name_prefix = var.name_prefix
  tags        = var.tags
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  table_name      = "SolidaryTechVolunteers"
  replica_regions = [var.dr_region]
  tags            = var.tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_names = [
    "solidarytech/ngo-service",
    "solidarytech/donation-service",
    "solidarytech/volunteer-service",
  ]

  enable_replication             = true
  replication_destination_region = var.dr_region

  tags = var.tags
}

module "irsa" {
  source = "../../modules/irsa"

  name_prefix = var.name_prefix

  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_oidc_provider_url = module.eks.oidc_provider_url

  sqs_queue_arn       = module.sqs.queue_arn
  dynamodb_table_arn  = module.dynamodb.table_arn
  ecr_repository_arns = module.ecr.repository_arns

  github_org  = var.github_org
  github_repo = var.github_repo

  tags = var.tags
}
