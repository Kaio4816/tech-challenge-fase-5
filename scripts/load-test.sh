#!/usr/bin/env bash
# Gera carga contra POST /donations (o Hot Path) para sustentar a demo de
# MTTR da Fase 5 (PROJECT_SPEC): sobe carga com este script, injeta uma
# falha (ex.: `kubectl -n solidarytech delete pod -l app.kubernetes.io/name=donation-service`
# ou escalar ngo-service para 0), observa o alerta no Prometheus/dashboard
# Grafana (gitops/platform/) e o self-heal do ArgoCD/HPA, cronometrando o
# MTTR.
#
# Requer `hey` (https://github.com/rakyll/hey): brew install hey
#
# Uso (contra o cluster real, via port-forward):
#   kubectl -n solidarytech port-forward svc/donation-service 8082:8082 &
#   kubectl -n solidarytech port-forward svc/ngo-service 8081:8081 &
#   ./scripts/load-test.sh [duracao] [concorrencia]
#
# Uso (contra o docker compose local):
#   BASE_URL=http://localhost:8082 NGO_SERVICE_URL=http://localhost:8081 \
#     ./scripts/load-test.sh 2m 10
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8082}"
NGO_SERVICE_URL="${NGO_SERVICE_URL:-http://localhost:8081}"
DURATION="${1:-${DURATION:-5m}}"
CONCURRENCY="${2:-${CONCURRENCY:-20}}"

if ! command -v hey >/dev/null 2>&1; then
  echo "Erro: 'hey' não encontrado no PATH. Instale com 'brew install hey'." >&2
  exit 1
fi

if [[ -z "${NGO_ID:-}" ]]; then
  echo "==> NGO_ID não definido — criando uma ONG de teste em ${NGO_SERVICE_URL}/ngos..."
  NGO_JSON="$(curl -sf -X POST "${NGO_SERVICE_URL}/ngos" \
    -H 'Content-Type: application/json' \
    -d '{"name":"ONG Load Test","email":"loadtest@solidarytech.example","cause":"Educação","city":"São Paulo"}')"
  NGO_ID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "${NGO_JSON}")"
  echo "==> Usando NGO_ID=${NGO_ID}"
fi

BODY="$(printf '{"ngo_id": %s, "amount": 25.5, "donor_name": "Load Test"}' "${NGO_ID}")"

echo "==> Disparando carga contra ${BASE_URL}/donations por ${DURATION}, concorrência ${CONCURRENCY}..."
echo "==> Acompanhe o dashboard 'SolidaryTech - SRE Golden Metrics & SLO' no Grafana durante a execução."
hey -z "${DURATION}" -c "${CONCURRENCY}" -m POST -T application/json -d "${BODY}" "${BASE_URL}/donations"
