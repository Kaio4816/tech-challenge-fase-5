#!/usr/bin/env bash
# Conecta o kubectl ao EKS do envs/primary, cria os Secrets dos 3 serviços a
# partir dos outputs do Terraform (não versionados, não passam pelo
# provider kubernetes do TF — ver infra/terraform/envs/primary), e instala
# o ArgoCD apontado para o overlay primary.
#
# Pré-requisito: infra/terraform/envs/primary já aplicado (terraform apply).
#
# Uso:
#   REPO_URL=https://github.com/SEU_USUARIO/hackathon-solidarytech.git \
#     ./scripts/deploy-primary.sh
set -euo pipefail

: "${REPO_URL:?defina REPO_URL com a URL do repositório GitHub (ex.: https://github.com/SEU_USUARIO/hackathon-solidarytech.git)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${REPO_ROOT}/infra/terraform/envs/primary"
REGION="us-east-1"
NAMESPACE="solidarytech"

echo "==> Lendo outputs do Terraform (${TF_DIR})..."
cd "${TF_DIR}"
CLUSTER_NAME="$(terraform output -raw cluster_name)"
RDS_ENDPOINT="$(terraform output -raw rds_endpoint)"
RDS_USER="$(terraform output -raw rds_master_username)"
RDS_PASSWORD="$(terraform output -raw rds_master_password)"
SQS_URL="$(terraform output -raw sqs_queue_url)"
DYNAMODB_TABLE="$(terraform output -raw dynamodb_table_name)"
RDS_HOST="${RDS_ENDPOINT%%:*}"

echo "==> Configurando kubectl para o cluster ${CLUSTER_NAME}..."
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"

echo "==> Garantindo o namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Criando/atualizando Secrets a partir dos outputs do Terraform..."
kubectl -n "${NAMESPACE}" create secret generic ngo-service-secrets \
  --from-literal=DATABASE_URL="postgres://${RDS_USER}:${RDS_PASSWORD}@${RDS_HOST}:5432/ngo_db" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic donation-service-secrets \
  --from-literal=DATABASE_URL="postgres://${RDS_USER}:${RDS_PASSWORD}@${RDS_HOST}:5432/donation_db" \
  --from-literal=AWS_SQS_URL="${SQS_URL}" \
  --from-literal=AWS_REGION="${REGION}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic volunteer-service-secrets \
  --from-literal=AWS_DYNAMODB_TABLE="${DYNAMODB_TABLE}" \
  --from-literal=AWS_REGION="${REGION}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Instalando ArgoCD e aplicando a Application raiz (env=primary)..."
REPO_URL="${REPO_URL}" "${REPO_ROOT}/gitops/bootstrap/install.sh" primary

echo "==> Pronto. Acompanhe com: kubectl -n argocd get applications"
