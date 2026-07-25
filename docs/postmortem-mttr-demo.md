# Post-Mortem — Degradação de latência no Hot Path por indisponibilidade do ngo-service

> **Status: ensaio ainda não executado contra o cluster real.**
> Este é o post-mortem do incidente **injetado deliberadamente** na demo de
> MTTR (Fase 5 do `PROJECT_SPEC`). O cenário, o mecanismo de detecção, o
> mecanismo de recuperação e as ações corretivas são determinados pelo desenho
> do sistema e estão preenchidos abaixo. Os **campos cronometrados** (marcados
> com `⏱ <medir>`) só podem ser preenchidos executando o roteiro da seção
> "Reprodução" contra o cluster real — a demo de MTTR é a pendência conhecida
> da Fase 5 (New Relic + `terraform apply` do `envs/primary`, ver `CLAUDE.md`).
> Está publicado neste estado, e não omitido, para que fique explícito o que já
> é conclusão de projeto e o que ainda é medição pendente.

## Resumo

| Campo | Valor |
|---|---|
| **Data** | ⏱ `<medir>` |
| **Severidade** | `warning` (latência), escalando para `critical` se o `ngo-service` não retornar |
| **Serviço afetado** | `donation-service` (Hot Path) — degradado por dependência |
| **Causa imediata** | `ngo-service` escalado para 0 réplicas (falha injetada) |
| **Ambiente** | `primary` (us-east-1) |
| **Início do impacto** | ⏱ `<medir>` |
| **Detecção** | ⏱ `<medir>` (esperado: +2 a 7 min — janela de 5m do p95 + `for: 5m`) |
| **Mitigação aplicada** | ⏱ `<medir>` (automática: `selfHeal` do ArgoCD) |
| **Fim do impacto** | ⏱ `<medir>` |
| **MTTD** | ⏱ `<medir>` |
| **MTTR** | ⏱ `<medir>` — **meta: < 5 min** |
| **Autor(es)** | Equipe de Plataforma SolidaryTech |

Durante um teste de carga sustentado no Hot Path (`POST /donations`), o
`ngo-service` — dependência de validação do `ngo_id` — foi levado a zero
réplicas. O `donation-service` **continuou aceitando e registrando doações**
(comportamento fail-open deliberado), mas cada requisição passou a esperar o
timeout de 2s da validação, degradando a latência p95 para muito acima do SLO
de 300ms. O `selfHeal` do ArgoCD detectou a divergência em relação ao estado
declarado no Git e restaurou o `ngo-service` sem intervenção humana.

## Impacto

- **Usuários/negócio**: doações **continuaram sendo processadas e persistidas**
  durante todo o incidente. O impacto foi de **experiência** (confirmação
  lenta, ~2s adicionais por doação), não de perda.
- **SLI afetado**: **latência** de `POST /donations` (p95). O SLI de
  **disponibilidade não foi afetado** — nenhum 5xx foi gerado.
- **Consumo de error budget**: **zero**. O error budget de 43,2 min/30d está
  atrelado ao SLI de disponibilidade (respostas não-5xx); um incidente
  puramente de latência não o consome. Esta é uma constatação relevante do
  ensaio, não um detalhe: o desenho fail-open converte indisponibilidade de
  dependência em degradação de latência, protegendo o error budget e a doação
  ao custo da experiência.
- **SLA externo (99,5%)**: **não violado** (o SLA é de disponibilidade).
- **Dados**: nenhuma perda. Nenhum failover envolvido.

## Detecção

- **Como foi detectado**: alerta `DonationServiceHighLatencyP95` do Prometheus
  (p95 de `/donations` > 300ms por 5 min) — ver
  `gitops/platform/prometheusrules/donation-service-slo.yaml`. Em paralelo,
  `SolidaryTechTargetDown` para o `job="ngo-service"` (scrape falhando) e,
  quando a conta New Relic estiver ativa, a condição
  `donation-service: anomalia de latencia (baseline)`, que deve disparar
  **antes** da estática por não depender de cruzar os 300ms.
- **O alerta funcionou como esperado?** ⏱ `<medir>` — a checagem específica é
  se o alerta de **latência** dispara e o de **taxa de erro** não. Um alerta de
  erro disparando aqui indicaria que o fail-open não está funcionando como
  projetado (regressão em `apps/donation-service/main.go`).
- **Evidência a capturar**: painel de latência p50/p95/p99 do dashboard
  "SolidaryTech - SRE Golden Metrics & SLO" no momento do degrau; lista de
  alertas `Firing` no Prometheus; issue correspondente no New Relic.

## Linha do tempo

| Hora (UTC) | Evento |
|---|---|
| ⏱ `<medir>` | `./scripts/load-test.sh 10m 20` — carga estável no Hot Path, p95 dentro do SLO |
| ⏱ `<medir>` | **Falha injetada**: `kubectl -n solidarytech scale deploy/ngo-service --replicas=0` |
| ⏱ `<medir>` | p95 de `POST /donations` sobe para ~2s (timeout da validação `donation → ngo`) |
| ⏱ `<medir>` | `SolidaryTechTargetDown{job="ngo-service"}` → `Firing` |
| ⏱ `<medir>` | `DonationServiceHighLatencyP95` → `Firing`; Alertmanager agrupa e o Workflow do New Relic notifica o plantão |
| ⏱ `<medir>` | ArgoCD detecta `OutOfSync` (réplicas ≠ 1 declarado no Git) e aplica `selfHeal` |
| ⏱ `<medir>` | Pod do `ngo-service` `Ready`; p95 volta abaixo de 300ms |
| ⏱ `<medir>` | Alertas resolvidos; e-mail de `CLOSED` do Workflow — fim da contagem de MTTR |

## Causa raiz

A causa raiz do **incidente ensaiado** é a injeção deliberada. O que o ensaio
de fato investiga é a cadeia de propagação:

1. Por que a latência do Hot Path degradou? → Porque cada `POST /donations`
   chama `GET /ngos/<id>` no `ngo-service` para validar o `ngo_id`.
2. Por que a chamada demorou 2s em vez de falhar rápido? → Porque não havia
   pod para recusar a conexão de imediato; o `Service` sem endpoints faz a
   requisição esperar até o timeout de `ngoValidationTimeout = 2s`.
3. Por que 2s de espera afetam o p95 inteiro? → Porque a validação é
   **síncrona** no caminho da doação (antes da resposta ao doador).
4. Por que nenhuma doação falhou, apesar disso? → Porque a validação é
   **fail-open**: erro de rede/timeout não bloqueia a gravação (só um `404`
   explícito rejeita).
5. Por que o serviço voltou sozinho? → Porque `replicas: 1` está **declarado no
   Git** e a Application do `ngo-service` tem `selfHeal: true` — o
   `kubectl scale` é drift, e o ArgoCD reverte drift por definição.

**Conclusão de projeto** (não uma falha a corrigir): a arquitetura troca
disponibilidade da dependência por latência do Hot Path, e a recuperação é
automática porque o estado desejado vive no Git, não no cluster.

## Resolução

**Automática**, sem ação humana: `selfHeal` do ArgoCD restaurou
`replicas: 1`. Nenhum `kubectl` corretivo foi necessário — e, se alguém tivesse
tentado corrigir manualmente, o resultado seria o mesmo (o ArgoCD é a única
fonte da verdade).

Limite conhecido: o intervalo de reconciliação padrão do ArgoCD (~3 min) é o
piso do MTTR neste modo de falha. É por isso que a meta é "< 5 min" e não
"< 1 min".

## O que funcionou bem (esperado)

- Detecção por **latência**, não por erro — o alerta certo para o sintoma real.
- Recuperação **automática** via GitOps, sem runbook manual.
- Fail-open protegeu a doação: zero perda de dado, zero consumo de error budget.
- Alertmanager agrupou `TargetDown` + `HighLatencyP95` como um único incidente
  (`group_by` inclui `service`), evitando dois chamados para o mesmo problema.

## O que não funcionou / poderia ser melhor

- **O piso de ~3 min do MTTR é do ArgoCD, não do sistema**: um webhook do
  GitHub para o ArgoCD reduziria o tempo de detecção de drift, mas exigiria
  expor o `argocd-server` (ALB, ~US$ 20/mês — ver
  [`finops-forecast.md`](finops-forecast.md)). Trade-off consciente.
- **Não há circuit breaker na validação `donation → ngo`**: com o
  `ngo-service` fora, cada requisição paga 2s de timeout. Um breaker que
  abrisse após N falhas consecutivas transformaria a degradação de ~2s em
  ~0ms — o fail-open já está lá, falta só falhar *rápido*.
- **O SLI de latência não tem error budget próprio**: o orçamento formal só
  cobre disponibilidade, então um incidente como este não aparece em nenhum
  contador acumulado. Definir um budget de latência daria visibilidade a essa
  classe de degradação.

## Ações corretivas

| # | Ação | Tipo | Dono | Prazo | Status |
|---|---|---|---|---|---|
| 1 | Executar o ensaio cronometrado e preencher os campos `⏱ <medir>` deste documento | detectar | Plataforma | antes da gravação do vídeo | **aberto** |
| 2 | Avaliar circuit breaker (ou timeout adaptativo) na validação `donation → ngo` | mitigar | Plataforma | backlog | aberto |
| 3 | Definir error budget de latência (além do de disponibilidade) em `sre-slo.md` | detectar | Plataforma | backlog | aberto |
| 4 | Avaliar webhook GitHub → ArgoCD para reduzir o piso de 3 min do MTTR | mitigar | Plataforma | backlog (depende de expor `argocd-server`) | aberto |

## Reprodução (roteiro do ensaio)

```bash
# Pré-requisito: envs/primary aplicado + deploy-primary.sh executado,
# 3 Applications Healthy/Synced.

# 1) Carga estável no Hot Path (deixar rodando em outro terminal)
kubectl -n solidarytech port-forward svc/donation-service 8082:8082 &
kubectl -n solidarytech port-forward svc/ngo-service 8081:8081 &
./scripts/load-test.sh 10m 20

# 2) Abrir dashboard + alertas (outros terminais)
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

# 3) Injetar a falha — anotar o timestamp EXATO:
date -u +%H:%M:%S && kubectl -n solidarytech scale deploy/ngo-service --replicas=0

# 4) Acompanhar (sem intervir!) a detecção e o self-heal:
kubectl -n solidarytech get pods -w
kubectl -n argocd get application ngo-service -w

# 5) Anotar o timestamp em que o p95 volta a < 300ms no dashboard:
date -u +%H:%M:%S

# MTTR = (passo 5) - (passo 3)
```

## Comunicação realizada

| Público | Quando | Canal | Link/modelo |
|---|---|---|---|
| Plantão técnico | no disparo do alerta | e-mail (Workflow New Relic, trigger `ACTIVATED`) | automático |
| Diretoria | não aplicável | — | incidente durou < 15 min e não afetou disponibilidade |
| ONGs parceiras | não aplicável | — | SLA de 99,5% não ameaçado (nenhum 5xx) |

Registro do critério: comunicação externa é acionada por ameaça ao SLA de
disponibilidade (ver [`itsm-incident-flow.md`](itsm-incident-flow.md#5-comunicação-aos-stakeholders)).
Um incidente de latência sem erro, resolvido automaticamente em minutos, é
tratado internamente — comunicar todo evento técnico a parceiro externo gera
ruído e desvaloriza a comunicação que realmente importa.
