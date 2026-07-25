# SLIs / SLOs / SLA — donation-service (Hot Path)

O `donation-service` é o caminho crítico da SolidaryTech: é onde as doações
são efetivamente processadas (`POST /donations`). Os demais serviços
(`ngo-service`, `volunteer-service`) não têm SLO formal nesta fase — o
foco de SRE está no fluxo que não pode parar.

## SLIs (Service Level Indicators)

Ambos os SLIs são medidos a partir das golden metrics já expostas em
`/metrics` pelo próprio serviço (`http_requests_total`,
`http_request_duration_seconds` — ver `apps/donation-service/main.go`),
escopados a `path="/donations"` (o endpoint de negócio; `/health` e
`/ready` são ruído de infraestrutura, não tráfego real de doação).

| SLI | Definição | Query (Prometheus) |
|---|---|---|
| Disponibilidade | proporção de respostas não-5xx em `POST /donations` | `sum(rate(http_requests_total{job="donation-service",path="/donations",status!~"5.."}[5m])) / sum(rate(http_requests_total{job="donation-service",path="/donations"}[5m]))` |
| Latência | p95 da duração de `POST /donations` | `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="donation-service",path="/donations"}[5m])) by (le))` |

## SLOs e SLA

| Métrica | SLO (interno) | SLA (externo, com as ONGs parceiras) |
|---|---|---|
| Disponibilidade | **99,9% em 30 dias** | 99,5% em 30 dias |
| Latência | **p95 < 300ms** | — (não contratual) |

O SLO é deliberadamente mais rígido que o SLA: a folga entre os dois é a
margem de segurança para agir (via os alertas abaixo) antes que o SLA
contratual seja de fato violado.

## Error budget

Com SLO de disponibilidade de 99,9%/30d, o orçamento de erro é:

```
30 dias = 43.200 minutos
Error budget = (1 - 0,999) × 43.200 min = 43,2 minutos / 30 dias
```

Ou seja: o `donation-service` pode ficar efetivamente indisponível
(respostas 5xx) por até 43,2 minutos em uma janela de 30 dias antes de
violar o SLO interno (e ainda ter alguma margem antes de violar o SLA de
99,5%, cujo orçamento seria de 216 min/30d).

### Budget restante (PromQL)

```promql
1 - (
  (
    sum(increase(http_requests_total{job="donation-service",path="/donations",status=~"5.."}[30d]))
    /
    sum(increase(http_requests_total{job="donation-service",path="/donations"}[30d]))
  )
  / 0.001
)
```

`0.001` é a fração de erro permitida pelo SLO (100% − 99,9%). O resultado
é a fração do orçamento de 30 dias que ainda resta (1 = orçamento
intacto, 0 = orçamento zerado, negativo = SLO já violado). Esta query
alimenta o gauge "Error budget restante" do dashboard (ver abaixo).

### Burn rate (multi-window, multi-burn-rate)

Em vez de alertar diretamente sobre a disponibilidade (o que ou dispara
tarde demais, ou gera ruído em picos curtos), os alertas usam **burn
rate**: a velocidade com que o error budget de 30 dias está sendo
consumido, seguindo a metodologia do Google SRE Workbook. Um burn rate de
`1` significa "consumindo o budget exatamente no ritmo sustentável para
30 dias"; um burn rate de `14.4` significa "no ritmo atual, o budget de
30 dias acabaria em ~2 dias".

As regras completas (recording rules + alerting rules) estão em
[`gitops/platform/prometheusrules/donation-service-slo.yaml`](../gitops/platform/prometheusrules/donation-service-slo.yaml):

| Severidade | Janela curta | Janela longa | Burn rate | Significado |
|---|---|---|---|---|
| `critical` (page) | 5m | 1h | > 14,4× | Budget de 30d esgotaria em ~2 dias |
| `warning` (ticket) | 30m | 6h | > 6× | Budget de 30d esgotaria em ~5 dias |

Cada alerta exige as duas janelas simultaneamente acima do limiar
(evita disparar por um pico isolado de poucos segundos que já saiu da
janela curta mas não chegou a afetar a janela longa).

Além do burn rate, há três alertas complementares no mesmo
`PrometheusRule`:
- `DonationServiceHighLatencyP95` — p95 de `/donations` acima de 300ms por 5 min.
- `SolidaryTechPodCrashLooping` — qualquer pod do namespace `solidarytech` em `CrashLoopBackOff`.
- `SolidaryTechTargetDown` — Prometheus não consegue coletar `/metrics` de um dos três serviços há mais de 2 min.

## Dashboard

[`gitops/platform/dashboards/sre-golden-metrics-dashboard.yaml`](../gitops/platform/dashboards/sre-golden-metrics-dashboard.yaml)
provisiona (via sidecar do Grafana, ConfigMap com label `grafana_dashboard: "1"`)
o dashboard **"SolidaryTech - SRE Golden Metrics & SLO (donation-service)"**:

- **Golden metrics**: traffic (req/s por status), errors (% de 5xx),
  latência p50/p95/p99, saturação de CPU/memória por pod.
- **SLO**: gauge de disponibilidade acumulada, gauge de error budget
  restante, gauge de burn rate atual (janela de 1h).

> **Limitação conhecida**: o Prometheus deste ambiente roda com
> `retention: 2d` (custo mínimo, infra efêmera — ver `kube-prometheus-stack-app.yaml`).
> As queries de burn rate (janelas de 5m a 6h) funcionam normalmente
> dentro dessa retenção. Já os gauges que usam janela de `30d`
> (disponibilidade acumulada, budget restante) só terão dados desde o
> instante em que o `terraform apply`/deploy daquele ciclo subiu o
> cluster — em uma demo de poucas horas, isso é o esperado e não invalida
> o exercício: o objetivo é demonstrar o *cálculo* funcionando com dados
> reais, não um histórico de 30 dias real (que exigiria o cluster no ar
> por 30 dias, incompatível com a estratégia de custo mínimo do projeto).

## Demo de MTTR — executada em 2026-07-25

O ensaio é automatizado por [`scripts/mttr-drill.sh`](../scripts/mttr-drill.sh);
o post-mortem completo, com a linha do tempo medida em UTC e as três previsões
que o ensaio refutou, está em
[`postmortem-mttr-demo.md`](postmortem-mttr-demo.md). Evidência bruta em
[`evidencias/mttr-detect/`](evidencias/mttr-detect/).

```bash
pkill -f port-forward   # túnel para pod morto invalida a medição
NGO_ID=<id> BASELINE_SECS=120 ./scripts/mttr-drill.sh detect 18m 8
```

**Resultados medidos** (falha injetada: `ngo-service` escalado a 0 réplicas,
sob carga de 8 conexões concorrentes em `POST /donations`):

| Métrica | Medido | Meta |
|---|---|---|
| p95 de linha de base | 21 ms | < 300 ms |
| p95 sob incidente | 1068 ms (em +54s) | — |
| p95 após recuperação | 17 ms | < 300 ms |
| **MTTD** | **424s (7min04s)** | — |
| **MTTR** (recuperação do GitOps) | **37s** | < 5 min |
| Alertas disparados | só `DonationServiceHighLatencyP95` | — |
| Error budget consumido | **zero** | — |

Três conclusões que mudam o entendimento do sistema:

1. **A recuperação é ~11x mais rápida que a detecção** (37s contra 424s). Sem
   retenção artificial, o `selfHeal` cura a falha ~6 min antes de o alerta
   acender — este modo de falha é praticamente invisível ao alerting.
2. **O fail-open foi comprovado**: indisponibilidade total da dependência
   virou latência, não erro. Nenhum 5xx, nenhum burn rate, error budget
   intacto.
3. **`SolidaryTechTargetDown` não cobre "réplicas a zero"**: com 0 réplicas a
   série `up` desaparece, e `up == 0` não casa com série ausente.

**Cuidado ao reproduzir**: com `c=20` a linha de base já nasce em ~830ms
(satura o `db.t4g.micro`) e o alerta passa a medir o gerador de carga em vez
do incidente. Use `c=8`.

O fluxo completo de tratamento/comunicação do incidente está em
[`itsm-incident-flow.md`](itsm-incident-flow.md).
