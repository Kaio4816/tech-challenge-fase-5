#!/usr/bin/env bash
# "Um comando" para ativar o warm standby (Fase 6 — Disaster Recovery):
#   1. snapshot mais recente do RDS do primary, copiado cross-region para o DR
#   2. terraform apply -auto-approve no envs/dr (restaura o Postgres a partir
#      da cópia, sobe EKS/SQS/IRSA na região de DR)
#   3. bootstrap do ArgoCD apontado para o overlay dr
#
# SQS e a réplica da Global Table (DynamoDB) já existem antes de rodar este
# script: SQS é recriada do zero pelo Terraform (fila de notificação, perda
# aceitável — ver docs/dr-plan.md); DynamoDB é a réplica que o envs/primary
# já mantém via Global Table (RPO ~0, nada a fazer aqui).
#
# Uso:
#   REPO_URL=https://github.com/SEU_USUARIO/hackathon-solidarytech.git \
#     ./scripts/activate-dr.sh
#
# Opcional:
#   DR_SNAPSHOT_ID=solidarytech-dr-20260101120000 ./scripts/activate-dr.sh
#     Pula a criação/cópia de um snapshot novo e reaplica usando uma cópia
#     já existente na região de DR (útil para reensaiar o terraform apply /
#     o sync do ArgoCD sem esperar de novo o snapshot+cópia, que é o passo
#     mais demorado). Sem essa variável, o script sempre cria uma cópia
#     fresca a partir do estado atual do primary (é isso que dá RPO baixo).
#
#   NEW_RELIC_LICENSE_KEY=... ./scripts/activate-dr.sh
#     Mesmo comportamento opcional do scripts/deploy-primary.sh (tracing
#     OTLP + Secret do nri-bundle). Sem ela, sobe como hoje, sem tracing.
#
#   RDS_INSTANCE_ID=solidarytech-primary-postgres ./scripts/activate-dr.sh
#     Pula o `terraform output` do envs/primary (que depende do state em
#     us-east-1) — mitigação para o ponto cego documentado no dr-plan.md:
#     numa falha genuína e total da região primária, o state no S3 pode
#     estar inacessível, mas o identificador da instância é estável e
#     conhecido.
#
# Pré-requisito: infra/terraform/envs/primary aplicado e com uma instância
# RDS em execução (é dela que o snapshot é tirado). Se o primary já estiver
# genuinamente inacessível (falha real de região, não só um ensaio), o
# script cai automaticamente para o snapshot mais recente já existente.
set -euo pipefail

: "${REPO_URL:?defina REPO_URL com a URL do repositório GitHub (ex.: https://github.com/SEU_USUARIO/hackathon-solidarytech.git)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRIMARY_TF_DIR="${REPO_ROOT}/infra/terraform/envs/primary"
DR_TF_DIR="${REPO_ROOT}/infra/terraform/envs/dr"
PRIMARY_REGION="us-east-1"
DR_REGION="us-east-2"
NAMESPACE="solidarytech"
MONITORING_NAMESPACE="monitoring"
NEW_RELIC_OTLP_ENDPOINT="https://otlp.nr-data.net:4318"
# Snapshots criados via CLI ficam fora do default_tags do Terraform — as
# tags FinOps obrigatórias do edital precisam ir explícitas aqui.
FINOPS_TAGS=(
  "Key=Project,Value=SolidaryTech"
  "Key=Environment,Value=Production"
  "Key=CostCenter,Value=NGO-Core"
)

START_TS="$(date +%s)"
echo "==> Ativação de DR iniciada em $(date -u +%Y-%m-%dT%H:%M:%SZ) (cronometrando RTO)."

if [[ -n "${DR_SNAPSHOT_ID:-}" ]]; then
  echo "==> DR_SNAPSHOT_ID definido — pulando criação/cópia de snapshot, reusando ${DR_SNAPSHOT_ID}."
  SNAPSHOT_ID="${DR_SNAPSHOT_ID}"
else
  if [[ -n "${RDS_INSTANCE_ID:-}" ]]; then
    echo "==> RDS_INSTANCE_ID definido via ambiente (${RDS_INSTANCE_ID}) — sem depender do state do primary."
  else
    echo "==> Lendo o identificador da instância RDS do primary..."
    RDS_INSTANCE_ID="$(terraform -chdir="${PRIMARY_TF_DIR}" output -raw rds_instance_id)"
  fi

  SNAPSHOT_ID="solidarytech-dr-$(date -u +%Y%m%d%H%M%S)"

  if aws rds describe-db-instances \
      --region "${PRIMARY_REGION}" \
      --db-instance-identifier "${RDS_INSTANCE_ID}" \
      >/dev/null 2>&1; then
    echo "==> Primary acessível — criando snapshot fresco ${SNAPSHOT_ID} (RPO = agora)..."
    SOURCE_SNAPSHOT_ID="${SNAPSHOT_ID}"
    aws rds create-db-snapshot \
      --region "${PRIMARY_REGION}" \
      --db-instance-identifier "${RDS_INSTANCE_ID}" \
      --db-snapshot-identifier "${SOURCE_SNAPSHOT_ID}" \
      --tags "${FINOPS_TAGS[@]}" \
      >/dev/null
    aws rds wait db-snapshot-available \
      --region "${PRIMARY_REGION}" \
      --db-snapshot-identifier "${SOURCE_SNAPSHOT_ID}"
    SOURCE_SNAPSHOT_ARN="$(aws rds describe-db-snapshots \
      --region "${PRIMARY_REGION}" \
      --db-snapshot-identifier "${SOURCE_SNAPSHOT_ID}" \
      --query 'DBSnapshots[0].DBSnapshotArn' \
      --output text)"
  else
    echo "==> Primary inacessível — caindo para o snapshot mais recente já existente (RPO = idade desse snapshot)."
    # Sem --snapshot-type, isso pode devolver um snapshot AUTOMÁTICO, cujo id
    # tem a forma "rds:<instância>-<ts>" — dois-pontos é inválido num
    # --target-db-snapshot-identifier. Por isso a origem (SOURCE_SNAPSHOT_ID)
    # e o alvo da cópia (SNAPSHOT_ID, sempre "solidarytech-dr-<ts>") são
    # variáveis separadas.
    SOURCE_SNAPSHOT_ID="$(aws rds describe-db-snapshots \
      --region "${PRIMARY_REGION}" \
      --db-instance-identifier "${RDS_INSTANCE_ID}" \
      --query 'reverse(sort_by(DBSnapshots, &SnapshotCreateTime))[0].DBSnapshotIdentifier' \
      --output text)"
    if [[ -z "${SOURCE_SNAPSHOT_ID}" || "${SOURCE_SNAPSHOT_ID}" == "None" ]]; then
      echo "Nenhum snapshot do RDS do primary encontrado em ${PRIMARY_REGION}. Abortando." >&2
      exit 1
    fi
    echo "==> Usando snapshot existente: ${SOURCE_SNAPSHOT_ID} (cópia no DR será ${SNAPSHOT_ID})"
    # O ARN vem por --db-instance-identifier (mesma query da escolha acima):
    # lookup por --db-snapshot-identifier exigiria --snapshot-type quando o
    # snapshot é automático ("rds:...") — e aqui ele tipicamente é.
    SOURCE_SNAPSHOT_ARN="$(aws rds describe-db-snapshots \
      --region "${PRIMARY_REGION}" \
      --db-instance-identifier "${RDS_INSTANCE_ID}" \
      --query 'reverse(sort_by(DBSnapshots, &SnapshotCreateTime))[0].DBSnapshotArn' \
      --output text)"
  fi

  echo "==> Copiando snapshot cross-region (${PRIMARY_REGION} -> ${DR_REGION})..."
  # Tags explícitas de novo: --copy-tags não é usado porque o snapshot de
  # origem pode ser um snapshot automático (fallback), que não tem as tags.
  aws rds copy-db-snapshot \
    --region "${DR_REGION}" \
    --source-region "${PRIMARY_REGION}" \
    --source-db-snapshot-identifier "${SOURCE_SNAPSHOT_ARN}" \
    --target-db-snapshot-identifier "${SNAPSHOT_ID}" \
    --tags "${FINOPS_TAGS[@]}" \
    >/dev/null
  aws rds wait db-snapshot-available \
    --region "${DR_REGION}" \
    --db-snapshot-identifier "${SNAPSHOT_ID}"
fi

echo "==> Snapshot pronto na região de DR: ${SNAPSHOT_ID}"

echo "==> terraform apply no envs/dr (restaura o Postgres, sobe EKS/SQS/IRSA em ${DR_REGION})..."
terraform -chdir="${DR_TF_DIR}" init -backend-config=backend.hcl -input=false >/dev/null
terraform -chdir="${DR_TF_DIR}" apply -auto-approve -input=false -var "snapshot_identifier=${SNAPSHOT_ID}"

echo "==> Lendo outputs do Terraform (${DR_TF_DIR})..."
CLUSTER_NAME="$(terraform -chdir="${DR_TF_DIR}" output -raw cluster_name)"
RDS_ENDPOINT="$(terraform -chdir="${DR_TF_DIR}" output -raw rds_endpoint)"
RDS_USER="$(terraform -chdir="${DR_TF_DIR}" output -raw rds_master_username)"
RDS_PASSWORD="$(terraform -chdir="${DR_TF_DIR}" output -raw rds_master_password)"
SQS_URL="$(terraform -chdir="${DR_TF_DIR}" output -raw sqs_queue_url)"
DYNAMODB_TABLE="$(terraform -chdir="${DR_TF_DIR}" output -raw dynamodb_table_name)"
RDS_HOST="${RDS_ENDPOINT%%:*}"

echo "==> Configurando kubectl para o cluster ${CLUSTER_NAME} (${DR_REGION})..."
aws eks update-kubeconfig --region "${DR_REGION}" --name "${CLUSTER_NAME}"

echo "==> Garantindo o namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Diferente do deploy-primary.sh: NÃO reaplicamos db/init.sql aqui. O
# Postgres já nasceu restaurado do snapshot com o schema e os dados do
# primary — é exatamente essa a prova de RPO que o ensaio verifica.

echo "==> Criando/atualizando Secrets a partir dos outputs do Terraform..."
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
  --from-literal=AWS_REGION="${DR_REGION}" \
  --from-literal=OTEL_SERVICE_NAME="donation-service" \
  "${OTEL_ARGS[@]+"${OTEL_ARGS[@]}"}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic volunteer-service-secrets \
  --from-literal=AWS_DYNAMODB_TABLE="${DYNAMODB_TABLE}" \
  --from-literal=AWS_REGION="${DR_REGION}" \
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

echo "==> Instalando ArgoCD e aplicando a Application raiz (env=dr)..."
REPO_URL="${REPO_URL}" "${REPO_ROOT}/gitops/bootstrap/install.sh" dr

END_TS="$(date +%s)"
ELAPSED=$(( END_TS - START_TS ))
echo "==> DR ativado. Tempo do script (snapshot->terraform apply->ArgoCD aplicado): $(( ELAPSED / 60 ))min $(( ELAPSED % 60 ))s."
echo "==> RTO real só fecha quando os pods ficarem Ready e o tráfego responder — acompanhe:"
echo "      kubectl -n argocd get applications"
echo "      kubectl -n ${NAMESPACE} get pods"
echo "==> Prova de RPO: confira se GET /donations na região de DR retorna as doações que já existiam no primary."
