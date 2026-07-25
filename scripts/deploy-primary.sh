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
#
# Opcional (Fase 5 — AIOps/tracing): defina NEW_RELIC_LICENSE_KEY para
# habilitar o export OTLP dos 3 serviços para o New Relic e criar o Secret
# que o nri-bundle (gitops/apps/base/nri-bundle-app.yaml) espera. Sem essa
# variável, os serviços sobem sem endpoint OTLP configurado (tracing
# permanece no-op, como hoje) e o Secret do nri-bundle não é criado — a
# Application correspondente no ArgoCD fica OutOfSync até a conta existir.
set -euo pipefail

: "${REPO_URL:?defina REPO_URL com a URL do repositório GitHub (ex.: https://github.com/SEU_USUARIO/hackathon-solidarytech.git)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${REPO_ROOT}/infra/terraform/envs/primary"
REGION="us-east-1"
NAMESPACE="solidarytech"
MONITORING_NAMESPACE="monitoring"
NEW_RELIC_OTLP_ENDPOINT="https://otlp.nr-data.net:4318"

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

echo "==> Aplicando o schema (CREATE TABLE) nos dois databases..."
# O Terraform (Fase 3) só cria os databases vazios via provider postgresql —
# o schema em si é responsabilidade da aplicação/deploy, igual ao
# docker-compose local. Idempotente (CREATE TABLE IF NOT EXISTS).
# PGCONNECT_TIMEOUT: o SG do RDS libera 5432 só para o IP de quem rodou o
# apply — se o IP mudou desde então, falha em 10s com erro claro em vez de
# travar minutos (rode `terraform apply -target=module.rds` para recalcular).
docker run --rm -e PGPASSWORD="${RDS_PASSWORD}" -e PGCONNECT_TIMEOUT=10 \
  -v "${REPO_ROOT}/apps/ngo-service/db/init.sql:/init.sql:ro" \
  postgres:16-alpine psql -h "${RDS_HOST}" -U "${RDS_USER}" -d ngo_db -f /init.sql
docker run --rm -e PGPASSWORD="${RDS_PASSWORD}" -e PGCONNECT_TIMEOUT=10 \
  -v "${REPO_ROOT}/apps/donation-service/db/init.sql:/init.sql:ro" \
  postgres:16-alpine psql -h "${RDS_HOST}" -U "${RDS_USER}" -d donation_db -f /init.sql

echo "==> Criando/atualizando Secrets a partir dos outputs do Terraform..."
# OTEL_EXPORTER_OTLP_* só entram nos Secrets se NEW_RELIC_LICENSE_KEY estiver
# definida — sem isso, os três serviços sobem exatamente como antes da Fase 5.
OTEL_ARGS=()
if [[ -n "${NEW_RELIC_LICENSE_KEY:-}" ]]; then
  OTEL_ARGS=(
    --from-literal=OTEL_EXPORTER_OTLP_ENDPOINT="${NEW_RELIC_OTLP_ENDPOINT}"
    --from-literal=OTEL_EXPORTER_OTLP_HEADERS="api-key=${NEW_RELIC_LICENSE_KEY}"
  )
fi

kubectl -n "${NAMESPACE}" create secret generic ngo-service-secrets \
  --from-literal=DATABASE_URL="postgres://${RDS_USER}:${RDS_PASSWORD}@${RDS_HOST}:5432/ngo_db" \
  --from-literal=OTEL_SERVICE_NAME="ngo-service" \
  "${OTEL_ARGS[@]+"${OTEL_ARGS[@]}"}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic donation-service-secrets \
  --from-literal=DATABASE_URL="postgres://${RDS_USER}:${RDS_PASSWORD}@${RDS_HOST}:5432/donation_db" \
  --from-literal=AWS_SQS_URL="${SQS_URL}" \
  --from-literal=AWS_REGION="${REGION}" \
  --from-literal=OTEL_SERVICE_NAME="donation-service" \
  "${OTEL_ARGS[@]+"${OTEL_ARGS[@]}"}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic volunteer-service-secrets \
  --from-literal=AWS_DYNAMODB_TABLE="${DYNAMODB_TABLE}" \
  --from-literal=AWS_REGION="${REGION}" \
  --from-literal=OTEL_SERVICE_NAME="volunteer-service" \
  "${OTEL_ARGS[@]+"${OTEL_ARGS[@]}"}" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${NEW_RELIC_LICENSE_KEY:-}" ]]; then
  echo "==> Criando o Secret newrelic-license (namespace ${MONITORING_NAMESPACE}) para o nri-bundle..."
  kubectl create namespace "${MONITORING_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "${MONITORING_NAMESPACE}" create secret generic newrelic-license \
    --from-literal=licenseKey="${NEW_RELIC_LICENSE_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "==> NEW_RELIC_LICENSE_KEY não definida — pulando OTLP/nri-bundle (tracing fica no-op)."
fi

echo "==> Instalando ArgoCD e aplicando a Application raiz (env=primary)..."
REPO_URL="${REPO_URL}" "${REPO_ROOT}/gitops/bootstrap/install.sh" primary

echo "==> Pronto. Acompanhe com: kubectl -n argocd get applications"
