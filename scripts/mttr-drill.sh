#!/usr/bin/env bash
# Ensaio cronometrado de MTTR, automatizado para que
# os números do post-mortem (docs/postmortem-mttr-demo.md) sejam MEDIDOS e não
# estimados.
#
# ---------------------------------------------------------------------------
# Por que DOIS modos
# ---------------------------------------------------------------------------
# O cenário original (escalar ngo-service para 0) tem um problema descoberto ao
# revisar as regras antes do ensaio:
#
#   * `SolidaryTechTargetDown` é `up{job=...} == 0`. Com o Deployment em 0
#     réplicas os Endpoints ficam vazios, o service discovery deixa de produzir
#     o target e a série `up` some -- série ausente NÃO satisfaz `== 0`.
#   * `DonationServiceHighLatencyP95` tem `for: 5m` sobre `rate(...[5m])`,
#     ~7 min até acender. O selfHeal do ArgoCD reverte o drift em ~3 min.
#
# Ou seja: no modo `selfheal` a recuperação chega ANTES da detecção e nenhum
# alerta dispara. Isso é um resultado legítimo (e uma constatação relevante do
# ensaio), mas não prova que a cadeia de alertas funciona.
#
#   modo `selfheal` (padrão) -- injeta `kubectl scale --replicas=0` e mede o
#     MTTR puro do laço GitOps, sem intervenção humana.
#
#   modo `detect` -- mesma injeção, mas o ensaio SEGURA o incidente aberto
#     (re-aplicando `--replicas=0` a cada 10s, lutando contra o selfHeal) até
#     o primeiro alerta acender. Só então solta, e o selfHeal recupera
#     sozinho. Assim o mesmo ensaio mede MTTD real (cadeia Prometheus ->
#     Alertmanager -> New Relic acendendo de verdade) e o tempo de
#     recuperação do GitOps a partir do instante em que ele é liberado.
#
# Nota sobre um caminho descartado: a primeira versão isolava o ngo-service com
# uma NetworkPolicy. Não funciona neste cluster -- o módulo EKS declara
# `vpc-cni = {}` sem `configuration_values`, e o AWS VPC CNI ignora
# NetworkPolicy silenciosamente a menos que `enableNetworkPolicy` esteja
# ligado. A policy seria aceita pela API e não teria efeito nenhum.
#
# Uso: ./scripts/mttr-drill.sh [selfheal|detect] [duracao_carga] [concorrencia]
set -euo pipefail

MODE="${1:-selfheal}"
DURATION="${2:-14m}"
CONCURRENCY="${3:-20}"

NS_APP="${NS_APP:-solidarytech}"
NS_MON="${NS_MON:-monitoring}"
PROM_SVC="${PROM_SVC:-kube-prometheus-stack-prometheus}"
BASELINE_SECS="${BASELINE_SECS:-180}"
POLL_SECS="${POLL_SECS:-10}"
TIMEOUT_SECS="${TIMEOUT_SECS:-1200}"

case "${MODE}" in
selfheal | detect) ;;
*)
  echo "Modo inválido: ${MODE} (use 'selfheal' ou 'detect')" >&2
  exit 1
  ;;
esac

OUT_DIR="${OUT_DIR:-docs/evidencias/mttr-${MODE}}"
mkdir -p "${OUT_DIR}"
TIMELINE="${OUT_DIR}/timeline.tsv"
: >"${TIMELINE}"

now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
now_epoch() { date -u +%s; }
log() { printf '%s\t%s\n' "$(now_utc)" "$1" | tee -a "${TIMELINE}"; }

cleanup() {
  local rc=$?
  # O holder é a única coisa que pode sobreviver ao script mantendo o serviço
  # derrubado -- matar sempre, inclusive em Ctrl-C, para que o selfHeal do
  # ArgoCD volte a ter a palavra final.
  [[ -n "${HOLDER_PID:-}" ]] && kill "${HOLDER_PID}" 2>/dev/null || true
  [[ -n "${PF_DON:-}" ]] && kill "${PF_DON}" 2>/dev/null || true
  [[ -n "${PF_NGO:-}" ]] && kill "${PF_NGO}" 2>/dev/null || true
  [[ -n "${PF_PROM:-}" ]] && kill "${PF_PROM}" 2>/dev/null || true
  [[ -n "${LOAD_PID:-}" ]] && kill "${LOAD_PID}" 2>/dev/null || true
  return $rc
}
trap cleanup EXIT

command -v hey >/dev/null 2>&1 || {
  echo "Erro: 'hey' não encontrado (brew install hey)." >&2
  exit 1
}

echo "==> Modo: ${MODE} | evidências em ${OUT_DIR}/"
echo "==> Abrindo port-forwards..."
kubectl -n "${NS_APP}" port-forward svc/donation-service 8082:8082 >/dev/null 2>&1 &
PF_DON=$!
kubectl -n "${NS_APP}" port-forward svc/ngo-service 8081:8081 >/dev/null 2>&1 &
PF_NGO=$!
kubectl -n "${NS_MON}" port-forward "svc/${PROM_SVC}" 9090:9090 >/dev/null 2>&1 &
PF_PROM=$!
sleep 8

prom_query() { curl -sf --get "http://localhost:9090/api/v1/query" --data-urlencode "query=$1" 2>/dev/null; }

# Só os alertas DESTE projeto. O kube-prometheus-stack traz dezenas de regras
# próprias (Watchdog, InfoInhibitor, KubeAggregatedAPIDown, CPUThrottlingHigh
# ...) e várias já ficam firing num cluster de demo -- na primeira execução do
# ensaio elas contaminaram o MTTD, que saiu como "3s" por causa de um
# InfoInhibitor que já estava aceso antes da falha ser injetada.
NOSSOS_ALERTAS="DonationServiceHighLatencyP95|DonationServiceErrorBudgetBurnRateCritical|DonationServiceErrorBudgetBurnRateWarning|SolidaryTechTargetDown|SolidaryTechPodCrashLooping"

firing_alerts() {
  curl -sf "http://localhost:9090/api/v1/alerts" 2>/dev/null |
    python3 -c '
import json,sys,re
pat=re.compile("^("+sys.argv[1]+")$")
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for a in d.get("data",{}).get("alerts",[]):
    n=a.get("labels",{}).get("alertname","")
    if a.get("state")=="firing" and pat.match(n):
        print(n)
' "${NOSSOS_ALERTAS}" | sort -u
}

# Mesma métrica/labels da regra DonationServiceHighLatencyP95; janela de 2m
# (e não 5m) só para o script reagir mais rápido que o alerta.
p95_ms() {
  prom_query 'histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="donation-service",path="/donations"}[2m]))) * 1000' |
    python3 -c '
import json,sys
try:
    r=json.load(sys.stdin)["data"]["result"]
    v=r[0]["value"][1] if r else "NaN"
    print("n/a" if v=="NaN" else "%.0f" % float(v))
except Exception: print("n/a")' 2>/dev/null || echo "n/a"
}

ngo_replicas() { kubectl -n "${NS_APP}" get deploy ngo-service -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?"; }
ngo_ready() {
  local r
  r="$(kubectl -n "${NS_APP}" get deploy ngo-service -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  echo "${r:-0}"
}

inject_failure() {
  log "T0_INICIO_IMPACTO	kubectl scale deploy/ngo-service --replicas=0"
  kubectl -n "${NS_APP}" scale deploy/ngo-service --replicas=0 >/dev/null

  if [[ "${MODE}" == "detect" ]]; then
    # Segura o incidente aberto re-aplicando o drift, para que a detecção
    # tenha tempo de acontecer. Sem isso o selfHeal (~3 min) recupera antes
    # do alerta de latência (~7 min: rate[5m] + for: 5m) chegar a acender.
    log "HOLDER_ATIVO	re-aplicando replicas=0 a cada 10s até o primeiro alerta"
    (
      while :; do
        sleep 10
        kubectl -n "${NS_APP}" scale deploy/ngo-service --replicas=0 >/dev/null 2>&1 || true
      done
    ) &
    HOLDER_PID=$!
  fi
}

repair_failure() {
  # No modo selfheal não há reparo: o ArgoCD é quem age.
  [[ "${MODE}" == "selfheal" ]] && return 0
  log "LIBERACAO	holder encerrado -- selfHeal do ArgoCD assume a recuperação"
  [[ -n "${HOLDER_PID:-}" ]] && kill "${HOLDER_PID}" 2>/dev/null || true
  HOLDER_PID=""
}

echo "==> Sanidade: alertas em firing antes de começar (esperado: nenhum)"
firing_alerts | sed 's/^/    - /' || true

# Sanidade dos túneis ANTES de começar a cronometrar. Numa execução anterior
# um port-forward apontava para um pod já substituído (o ngo-service tinha
# sido recriado pelo selfHeal); o load-test.sh morreu ao criar a ONG e o
# ensaio rodou 2 minutos inteiros medindo uma linha de base vazia, sem
# nenhuma requisição chegando.
for probe in "http://localhost:8081/health ngo-service" "http://localhost:8082/health donation-service" "http://localhost:9090/-/ready prometheus"; do
  set -- ${probe}
  if ! curl -sf --max-time 5 "$1" >/dev/null 2>&1; then
    echo "Erro: $2 inacessível em $1 -- port-forward não subiu ou aponta para pod morto." >&2
    echo "      Rode: pkill -f port-forward   e tente de novo." >&2
    exit 1
  fi
done
echo "==> Túneis OK (ngo-service, donation-service, prometheus)"

# Gerador de carga preexistente arruína a medição: a concorrência soma, o
# db.t4g.micro satura e a linha de base do p95 estoura os 300ms do SLO. A partir
# daí o alerta de latência mede a carga, não o incidente injetado -- aconteceu na
# rodada de 2026-07-30 (base 352ms, p95 na falha 351ms: variação nenhuma).
# Abortar é melhor que medir errado, porque o resultado errado *parece* válido.
if pgrep -f "hey -z" >/dev/null 2>&1; then
  echo "Erro: já existe gerador de carga rodando (hey -z):" >&2
  pgrep -lf "hey -z" | sed 's/^/      /' >&2
  echo >&2
  echo "      Este script sobe a sua própria carga. Duas juntas saturam o RDS e" >&2
  echo "      invalidam a linha de base do p95." >&2
  echo "      Rode:  pkill -f 'hey -z'   espere ~2min o p95 cair, e tente de novo." >&2
  exit 1
fi

log "INICIO_CARGA	load-test.sh ${DURATION} c=${CONCURRENCY}"
NGO_SERVICE_URL="http://localhost:8081" BASE_URL="http://localhost:8082" \
  ./scripts/load-test.sh "${DURATION}" "${CONCURRENCY}" >"${OUT_DIR}/hey-output.txt" 2>&1 &
LOAD_PID=$!

echo "==> Aquecendo ${BASELINE_SECS}s para estabelecer a linha de base..."
sleep "${BASELINE_SECS}"
BASE_P95="$(p95_ms)"
log "BASELINE_P95_MS	${BASE_P95}"

if [[ "${BASE_P95}" != "n/a" && "${BASE_P95}" -gt 300 ]]; then
  echo >&2
  echo "ERRO: linha de base (${BASE_P95}ms) já viola o SLO de 300ms ANTES da falha." >&2
  echo "      Com a base acima do limiar, o alerta de latência mede a carga e não" >&2
  echo "      o incidente -- o p95 não vai variar quando a dependência cair." >&2
  echo >&2
  echo "      Rode de novo com concorrência menor (metade da atual):" >&2
  echo "        NGO_ID=${NGO_ID:-3} BASELINE_SECS=${BASELINE_SECS} \\" >&2
  echo "          ./scripts/mttr-drill.sh ${MODE} ${DURATION} $(( CONCURRENCY / 2 ))" >&2
  echo >&2
  echo "      Para seguir mesmo assim (a medição de latência será inválida):" >&2
  echo "        ALLOW_INVALID_BASELINE=1 ..." >&2
  log "BASELINE_INVALIDA	${BASE_P95}ms > 300ms"
  if [[ -z "${ALLOW_INVALID_BASELINE:-}" ]]; then
    kill "${LOAD_PID}" 2>/dev/null || true
    pkill -f "hey -z" 2>/dev/null || true
    exit 1
  fi
  echo "==> ALLOW_INVALID_BASELINE definido: seguindo com base inválida." >&2
fi

T0="$(now_epoch)"
inject_failure

# Confirma que a falha REALMENTE tirou o serviço do ar antes de começar a
# procurar recuperação. Sem isso o script pode ver o pod antigo ainda
# terminando (Ready) somado ao replicas=1 já restaurado pelo ArgoCD e
# declarar "recuperado" em segundos, sem ter havido indisponibilidade --
# foi o que aconteceu na primeira execução ("recuperado em +17s").
echo "==> Confirmando que o ngo-service ficou de fato indisponível..."
for _ in $(seq 1 30); do
  [[ "$(ngo_ready)" -eq 0 ]] && break
  sleep 2
done
if [[ "$(ngo_ready)" -eq 0 ]]; then
  log "FALHA_EFETIVA	ngo-service com 0 réplicas prontas	(+$(($(now_epoch) - T0))s)"
else
  log "AVISO	ngo-service nunca chegou a 0 réplicas prontas -- selfHeal foi mais rápido que a terminação do pod"
fi

T1=""
T_REPAIR=""
T3=""
T4=""
DEGRADED_LOGGED=""
SEEN_ALERTS=()

while :; do
  ELAPSED=$(($(now_epoch) - T0))
  if [[ ${ELAPSED} -gt ${TIMEOUT_SECS} ]]; then
    log "TIMEOUT	${TIMEOUT_SECS}s sem fechar o ciclo"
    break
  fi

  CUR_P95="$(p95_ms)"

  if [[ -z "${DEGRADED_LOGGED}" && "${CUR_P95}" != "n/a" && "${CUR_P95}" -gt 300 ]]; then
    log "DEGRADACAO_P95	p95=${CUR_P95}ms (SLO=300ms)	(+${ELAPSED}s)"
    DEGRADED_LOGGED=1
  fi

  while IFS= read -r a; do
    [[ -z "$a" ]] && continue
    already=""
    for s in ${SEEN_ALERTS[@]+"${SEEN_ALERTS[@]}"}; do [[ "$s" == "$a" ]] && already=1; done
    if [[ -z "${already}" ]]; then
      SEEN_ALERTS+=("$a")
      log "ALERTA_FIRING	${a}	(+${ELAPSED}s)"
      if [[ -z "${T1}" ]]; then
        T1="$(now_epoch)"
        log "T1_DETECCAO	primeiro alerta: ${a}	MTTD=$((T1 - T0))s"
      fi
    fi
  done < <(firing_alerts)

  # No modo detect, solta o holder assim que a detecção aconteceu -- daí em
  # diante o selfHeal do ArgoCD recupera sozinho.
  if [[ "${MODE}" == "detect" && -n "${T1}" && -z "${T_REPAIR}" ]]; then
    T_REPAIR="$(now_epoch)"
    repair_failure
  fi

  if [[ -z "${T3}" && "$(ngo_replicas)" == "1" && "$(ngo_ready)" -ge 1 ]]; then
    if [[ "${MODE}" == "selfheal" ]]; then
      T3="$(now_epoch)"
      log "T3_SELFHEAL_RECUPERADO	ArgoCD restaurou replicas=1 e pod Ready	(+$((T3 - T0)))s"
    elif [[ -n "${T_REPAIR}" ]]; then
      T3="$(now_epoch)"
      log "T3_RECUPERADO	conectividade restaurada	(+$((T3 - T0)))s"
    fi
  fi

  if [[ -n "${T3}" && -z "${T4}" ]]; then
    if [[ -z "$(firing_alerts)" && -n "${T1}" ]]; then
      T4="$(now_epoch)"
      log "T4_FIM_IMPACTO	alertas resolvidos	MTTR=$((T4 - T0))s"
      break
    fi
    # No modo selfheal pode não haver alerta nenhum: fecha quando o serviço
    # voltou e a latência normalizou.
    if [[ -z "${T1}" && "${CUR_P95}" != "n/a" && "${CUR_P95}" -le 300 && $((ELAPSED - (T3 - T0))) -ge 60 ]]; then
      T4="$(now_epoch)"
      log "T4_FIM_IMPACTO	p95 normalizado, nenhum alerta chegou a disparar	MTTR=$((T4 - T0))s"
      break
    fi
  fi

  sleep "${POLL_SECS}"
done

FINAL_P95="$(p95_ms)"
log "P95_FINAL_MS	${FINAL_P95}"

kubectl -n "${NS_APP}" get pods -o wide >"${OUT_DIR}/pods-final.txt" 2>&1 || true
kubectl -n argocd get applications -o wide >"${OUT_DIR}/argocd-applications.txt" 2>&1 || true
curl -sf "http://localhost:9090/api/v1/rules" >"${OUT_DIR}/prometheus-rules.json" 2>/dev/null || true
curl -sf "http://localhost:9090/api/v1/alerts" >"${OUT_DIR}/prometheus-alerts-final.json" 2>/dev/null || true

{
  echo "# Ensaio de MTTR -- modo ${MODE}"
  echo
  echo "Executado em: $(now_utc) (UTC)"
  echo "Baseline p95: ${BASE_P95} ms | p95 final: ${FINAL_P95} ms"
  echo
  if [[ -n "${T1}" ]]; then
    echo "MTTD = $((T1 - T0))s"
  else
    echo "MTTD = n/a -- nenhum alerta disparou antes da recuperação"
  fi
  [[ -n "${T3}" ]] && echo "Serviço recuperado em +$((T3 - T0))s"
  [[ -n "${T_REPAIR}" ]] && echo "Holder liberado (selfHeal assume) em +$((T_REPAIR - T0))s"
  if [[ -n "${T4}" ]]; then
    echo "MTTR = $((T4 - T0))s (meta: < 300s)"
  else
    echo "MTTR = não fechado dentro de ${TIMEOUT_SECS}s"
  fi
  echo
  echo "Alertas que dispararam: ${SEEN_ALERTS[*]+${SEEN_ALERTS[*]}}"
} | tee "${OUT_DIR}/resumo.txt"

echo
echo "==> Evidências em ${OUT_DIR}/"
