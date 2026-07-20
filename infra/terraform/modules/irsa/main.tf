# Três roles IAM assumíveis via OIDC (IRSA), sem nenhuma access key:
#   - donation-service: só pode publicar (sqs:SendMessage) na fila de eventos
#   - volunteer-service: CRUD na tabela DynamoDB
#   - github-actions: só pode autenticar e dar push nos 3 repositórios ECR
#     (usada pelo job "push" dos workflows de CI, ver .github/workflows)

# ---------------------------------------------------------------------------
# donation-service -> SQS
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "donation_sa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:donation-service"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "donation_service" {
  name               = "${var.name_prefix}-donation-service"
  assume_role_policy = data.aws_iam_policy_document.donation_sa_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "donation_sqs" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [var.sqs_queue_arn]
  }
}

resource "aws_iam_role_policy" "donation_sqs" {
  name   = "sqs-send"
  role   = aws_iam_role.donation_service.id
  policy = data.aws_iam_policy_document.donation_sqs.json
}

# ---------------------------------------------------------------------------
# volunteer-service -> DynamoDB
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "volunteer_sa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:volunteer-service"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "volunteer_service" {
  name               = "${var.name_prefix}-volunteer-service"
  assume_role_policy = data.aws_iam_policy_document.volunteer_sa_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "volunteer_dynamodb" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [var.dynamodb_table_arn, "${var.dynamodb_table_arn}/index/*"]
  }
}

resource "aws_iam_role_policy" "volunteer_dynamodb" {
  name   = "dynamodb-crud"
  role   = aws_iam_role.volunteer_service.id
  policy = data.aws_iam_policy_document.volunteer_dynamodb.json
}

# ---------------------------------------------------------------------------
# GitHub Actions -> push de imagens no ECR
# ---------------------------------------------------------------------------

# Thumbprint obtido dinamicamente (handshake TLS real) em vez de hardcoded:
# a AWS exige o valor, mas na prática ignora-o para provedores conhecidos
# como o do GitHub — buscar ao vivo evita depender de um hash que fica
# desatualizado se o GitHub rotacionar o certificado novamente.
data "tls_certificate" "github" {
  count = var.create_github_actions_role && var.create_github_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_actions_role && var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = var.tags
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_actions_role && !var.create_github_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? try(aws_iam_openid_connect_provider.github[0].arn, null) : try(data.aws_iam_openid_connect_provider.github[0].arn, null)
}

data "aws_iam_policy_document" "github_actions_trust" {
  count = var.create_github_actions_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # O claim "sub" do GitHub inclui IDs numéricos imutáveis colados no
      # nome (ex.: "repo:org@123/repo@456:ref:refs/heads/main"), não só
      # "repo:org/repo:...". Os "*" cobrem esse sufixo em ambos os lados.
      values = ["repo:${var.github_org}*/${var.github_repo}*:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = var.create_github_actions_role ? 1 : 0

  name               = "${var.name_prefix}-github-actions-ecr"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "github_actions_ecr" {
  count = var.create_github_actions_role ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  count = var.create_github_actions_role ? 1 : 0

  name   = "ecr-push"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_ecr[0].json
}
