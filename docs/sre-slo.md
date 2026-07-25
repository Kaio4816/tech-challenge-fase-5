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

## Demo de MTTR (roteiro)

1. Gerar carga sustentada contra o hot path:
   ```bash
   kubectl -n solidarytech port-forward svc/donation-service 8082:8082 &
   kubectl -n solidarytech port-forward svc/ngo-service 8081:8081 &
   ./scripts/load-test.sh 10m 20
   ```
2. Com o dashboard aberto (Grafana) e a lista de alertas do Prometheus
   visível, injetar uma falha real, por exemplo:
   ```bash
   kubectl -n solidarytech scale deploy/ngo-service --replicas=0
   # ou: kubectl -n solidarytech delete pod -l app.kubernetes.io/name=donation-service
   # ou: kustomize edit set image donation-service=<tag-quebrada> (via CI) + push
   ```
3. Observar: burn rate/latência sobem no dashboard → alerta dispara no
   Prometheus (Alertmanager) → (quando a conta New Relic existir) anomalia
   também sinalizada pelo Applied Intelligence.
4. Observar a recuperação: self-heal do ArgoCD (`kubectl scale` de volta,
   ou o HPA/liveness probe reiniciando o pod quebrado) ou rollback via
   GitOps (revert do commit de imagem).
5. Cronometrar do início do impacto (primeiro 5xx/latência alta no
   dashboard) até a normalização (burn rate volta a < 1×) — meta: **MTTR
   < 5 minutos**. Registrar o tempo medido e a causa em
   [`postmortem-mttr-demo.md`](postmortem-mttr-demo.md) (o post-mortem já
   está escrito com o cenário e as ações; faltam os campos cronometrados).
   O fluxo completo de tratamento/comunicação do incidente está em
   [`itsm-incident-flow.md`](itsm-incident-flow.md).
