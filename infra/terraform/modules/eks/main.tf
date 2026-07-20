# Cluster EKS custo-mínimo: endpoint público (evita bastion), 1 managed node
# group em Spot, addons gerenciados pela AWS (vpc-cni, coredns, kube-proxy,
# metrics-server) + aws-ebs-csi-driver (precisa de uma role IRSA que só
# existe depois que o cluster e seu OIDC provider já foram criados — por
# isso vira um aws_eks_addon avulso em vez de entrar em cluster_addons, que
# criaria um ciclo entre os dois módulos).

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns        = {}
    kube-proxy     = {}
    vpc-cni        = {}
    metrics-server = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = {
        role = "general"
      }

      tags = var.tags
    }
  }

  tags = var.tags
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn

  tags = var.tags

  depends_on = [module.eks]
}
