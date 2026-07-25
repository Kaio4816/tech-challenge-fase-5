# Evidências da verificação contra a AWS real — 2026-07-25

Coletadas durante a janela de verificação da Fase 5, com a infraestrutura de
fato aplicada em `us-east-1` (destruída ao final, por design — ver
[`finops-forecast.md`](../finops-forecast.md)).

| Pasta / arquivo | O que comprova |
|---|---|
| `cicd/pipeline-jobs.txt` | Pipeline completo verde nos 3 serviços, 8 jobs cada: test, Semgrep, **SonarCloud**, SCA, build, Trivy, push ECR via OIDC, bump GitOps |
| `cluster/argocd-applications.txt` | As 9 Applications do ArgoCD `Synced`/`Healthy` |
| `cluster/nodes.txt` | 4 nós Spot t3.medium |
| `cluster/solidarytech-workloads.txt` | Os 3 serviços rodando + HPA do donation-service |
| `cluster/monitoring-workloads.txt` | Prometheus, Alertmanager, Grafana, Loki, Promtail e nri-bundle de pé; PVCs `Bound` em `gp2` |
| `cluster/platform-crs.txt` | ServiceMonitors e PrometheusRule aplicados via GitOps |
| `cluster/finops-recursos-taggeados.txt` | 59 recursos AWS com as 3 tags obrigatórias |
| `cluster/finops-exemplo-tags.json` | Tags `Project`/`Environment`/`CostCenter` num recurso real |
| `newrelic/nrql-evidencias.txt` | **Trace distribuído** (traces com 2 serviços e 3 spans), spans por serviço e infra K8s via nri-bundle |
| `mttr-detect/timeline.tsv` | Cronologia do ensaio de MTTR em UTC |
| `mttr-detect/resumo.txt` | MTTD 424s, recuperação 37s, p95 21ms → 1068ms → 17ms |
| `mttr-detect/prometheus-alerts-final.json` | Estado dos alertas ao fim do ensaio |
| `mttr-detect/hey-output.txt` | Saída do gerador de carga |
| `mttr-selfheal/` | Primeira execução do ensaio — **inválida como medição** (linha de base já acima do SLO por excesso de concorrência, e alertas do próprio chart contaminando o MTTD). Mantida de propósito: foi ela que revelou os dois problemas de método corrigidos no script |

## Limitação conhecida

O `newrelic_workflow` (roteamento de alerta para e-mail) **não pôde ser
criado**: a API do New Relic responde `MISSING_ENTITLEMENT` para a conta
usada, que é do plano free. As 2 policies e as 5 condições de alerta —
incluindo as duas `baseline` (anomaly detection) — foram aplicadas por
Terraform e estão ativas. Detalhes e encaminhamento na ação corretiva nº 7 do
[post-mortem](../postmortem-mttr-demo.md).
