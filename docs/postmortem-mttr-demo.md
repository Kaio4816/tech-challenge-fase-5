# Post-Mortem — Degradação de latência no Hot Path por indisponibilidade do ngo-service

> **Status: ensaio executado contra o cluster real em 2026-07-25.**
> Este é o post-mortem do incidente **injetado deliberadamente** na demo de
> MTTR (Fase 5 do `PROJECT_SPEC`). Todos os tempos abaixo foram **medidos**,
> não estimados — evidência bruta em
> [`evidencias/mttr-detect/`](evidencias/mttr-detect/) (timeline em UTC,
> saída do gerador de carga e estado dos alertas do Prometheus).
>
> O ensaio **refutou três previsões** feitas quando este documento foi escrito
> antes da execução. Elas estão corrigidas no texto e destacadas em
> "O que o ensaio refutou" — são a parte mais útil do exercício.

## Resumo

| Campo | Valor |
|---|---|
| **Data** | 2026-07-25 |
| **Severidade** | `warning` (latência) — nunca escalou para `critical` |
| **Serviço afetado** | `donation-service` (Hot Path) — degradado por dependência |
| **Causa imediata** | `ngo-service` escalado para 0 réplicas (falha injetada) |
| **Ambiente** | `primary` (us-east-1), 4 nós, carga de 8 conexões concorrentes em `POST /donations` |
| **Início do impacto** | 20:18:43 UTC (falha efetiva às 20:18:47, +4s) |
| **Detecção** | 20:25:47 UTC — `DonationServiceHighLatencyP95` |
| **Mitigação aplicada** | 20:25:47 UTC (automática: `selfHeal` do ArgoCD, liberado nesse instante) |
| **Fim do impacto** | 20:29:39 UTC (alertas resolvidos); serviço já respondia normal às 20:26:24 |
| **MTTD** | **424s (7min04s)** |
| **MTTR** | **37s** medidos a partir do momento em que o GitOps foi autorizado a agir — ver a nota abaixo sobre o número de 656s |
| **Autor(es)** | Equipe de Plataforma SolidaryTech |

> **Sobre o MTTR — leia antes de citar o número.** A duração total do
> incidente foi de **656s**, mas **424s desses foram uma espera deliberada**:
> o ensaio segurou a falha aberta (re-aplicando `replicas=0` a cada 10s) para
> impedir que o `selfHeal` curasse o serviço **antes de o alerta acender**.
> Sem essa retenção não haveria nada a detectar, e a cadeia de alertas ficaria
> por provar. Assim que o holder foi liberado, a recuperação levou **37s**.
> Uma observação independente no mesmo cluster, sem retenção nenhuma, mediu
> **80s** entre o drift e o pod de volta `Ready`. O MTTR real deste modo de
> falha está, portanto, na casa de **37–80s — muito abaixo da meta de 5 min**.
> Os 656s medem o ensaio, não o sistema.

Durante um teste de carga sustentado no Hot Path (`POST /donations`), o
`ngo-service` — dependência de validação do `ngo_id` — foi levado a zero
réplicas. O `donation-service` **continuou aceitando e registrando doações**
(comportamento fail-open deliberado), mas cada requisição passou a esperar o
timeout de 2s da validação, degradando a latência p95 para muito acima do SLO
de 300ms. O `selfHeal` do ArgoCD detectou a divergência em relação ao estado
declarado no Git e restaurou o `ngo-service` sem intervenção humana.

## Impacto

- **Usuários/negócio**: doações **continuaram sendo processadas e persistidas**
  durante todo o incidente — confirmado no ensaio, com carga contínua de 8
  conexões concorrentes gravando no banco do começo ao fim. O impacto foi de
  **experiência** (confirmação lenta), não de perda.
- **SLI afetado**: **latência** de `POST /donations` (p95), que saiu de
  **21ms para 1068ms** em 54s e voltou a **17ms** ao final. O SLI de
  **disponibilidade não foi afetado** — nenhum 5xx foi gerado, e nenhum
  alerta de erro ou de burn rate chegou a disparar.
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
- **O alerta funcionou como esperado? Sim, e a checagem decisiva passou.** A
  pergunta era se dispararia o alerta de **latência** e **não** o de taxa de
  erro. Foi exatamente isso: o único alerta do projeto que acendeu em todo o
  ensaio foi `DonationServiceHighLatencyP95`. Nenhum alerta de burn rate de
  error budget disparou — prova empírica de que o fail-open está funcionando
  (a indisponibilidade da dependência virou latência, não 5xx) e de que o
  error budget não foi tocado.
- **Evidência capturada**: [`evidencias/mttr-detect/timeline.tsv`](evidencias/mttr-detect/timeline.tsv)
  (cronologia em UTC), `resumo.txt`, `prometheus-alerts-final.json` e
  `hey-output.txt`.

## Linha do tempo

| Hora (UTC) | Δ | Evento |
|---|---|---|
| 20:16:43 | — | `./scripts/mttr-drill.sh detect 18m 8` — carga estável no Hot Path |
| 20:18:43 | T0 | Linha de base medida: **p95 = 21ms** (SLO 300ms). **Falha injetada**: `kubectl -n solidarytech scale deploy/ngo-service --replicas=0` |
| 20:18:47 | +4s | Falha confirmada efetiva: `readyReplicas = 0` |
| 20:19:38 | +54s | p95 de `POST /donations` sobe para **1068ms** (timeout de 2s da validação `donation → ngo`) |
| 20:25:47 | +424s | `DonationServiceHighLatencyP95` → **`Firing`**. **MTTD = 7min04s**. Nenhum alerta de erro/burn rate acendeu |
| 20:25:47 | +424s | Retenção liberada — `selfHeal` do ArgoCD autorizado a agir |
| 20:26:24 | +461s | `ngo-service` de volta `Ready` — **37s após a liberação** |
| 20:29:39 | +656s | Alertas resolvidos; **p95 final = 17ms** |

Duas ausências notáveis nesta linha do tempo, ambas explicadas em "O que o
ensaio refutou":

- `SolidaryTechTargetDown` **não** disparou — limitação estrutural da regra,
  não falha do ensaio.
- **Não houve e-mail de notificação.** O Workflow do New Relic que faria esse
  roteamento não pôde ser criado: a API responde `MISSING_ENTITLEMENT` para a
  conta usada (plano free). As 2 policies e as 5 condições — incluindo as duas
  de `baseline`/anomalia — estão aplicadas via Terraform e ativas; o que falta
  é apenas o roteamento automático para e-mail. Ação corretiva nº 7.

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

**Medido: 37s** entre autorizar o GitOps a agir e o pod estar `Ready` de novo
(uma observação independente, sem retenção, mediu 80s).

> **Correção de uma premissa deste documento.** A versão pré-ensaio afirmava
> que "o intervalo de reconciliação padrão do ArgoCD (~3 min) é o piso do MTTR
> neste modo de falha". **Está errado.** O ArgoCD reage a drift por *watch* na
> API do Kubernetes, não esperando o ciclo de polling — por isso 37s, não
> 3 min. O intervalo de 3 min governa a detecção de mudanças **no Git**, que é
> outra coisa. A meta de "< 5 min" continua válida, mas com folga muito maior
> do que se supunha.
>
> Ressalva observada no ensaio: quando o drift é reaplicado repetidamente (o
> holder forçando `replicas=0` a cada 10s), o `selfHeal` entra em **backoff
> exponencial** e a recuperação passa a levar minutos. Isso não afeta um
> incidente real de evento único, mas é relevante para quem for reproduzir o
> ensaio.

## O que o ensaio refutou

Esta seção é a razão de o ensaio existir. Três afirmações escritas antes da
execução não sobreviveram ao contato com o cluster real.

**1. `SolidaryTechTargetDown` nunca vai disparar neste cenário.** A regra é
`up{job=~"..."} == 0`. Ao escalar o Deployment para zero, os Endpoints do
Service ficam vazios, o service discovery para de produzir o target e a série
`up{job="ngo-service"}` **deixa de existir** — e série ausente não satisfaz
`== 0`. A previsão original de que ela acenderia estava estruturalmente errada,
não foi azar de temporização. Consequência prática: **este alerta não cobre
"serviço escalado a zero"**, só cobre "serviço de pé mas com scrape falhando".
Cobrir o primeiro caso exige uma regra sobre `kube_deployment_status_replicas_available`
ou `absent(up{job="ngo-service"})` — ação corretiva nº 5.

**2. O piso de MTTR de ~3 min atribuído ao ArgoCD não existe.** Medimos 37s.
O `selfHeal` é acionado por watch, não por polling — ver "Resolução".

**3. Sem retenção, o incidente se cura antes de ser detectado.** Com MTTD de
424s e recuperação de 37s, o `selfHeal` fecharia a falha **cerca de 6 minutos
antes** de o alerta acender. Foi confirmado na primeira execução do ensaio, em
modo `selfheal` puro: o serviço voltou sozinho e nenhum alerta do projeto
chegou a disparar. **Este modo de falha é, na prática, invisível ao
alerting** — o sistema se cura mais rápido do que percebe. Não é um defeito
do GitOps (recuperar rápido é o objetivo), mas significa que a contagem de
incidentes por alerta subestima o que de fato acontece no cluster. É a
constatação mais importante do exercício e origina as ações corretivas 5 e 6.

## O que funcionou bem (esperado)

- Detecção por **latência**, não por erro — o alerta certo para o sintoma real,
  confirmado: foi o único alerta do projeto a disparar.
- Recuperação **automática** via GitOps em 37s, sem runbook manual e sem
  nenhum `kubectl` corretivo.
- Fail-open protegeu a doação: durante os ~11 min de incidente as doações
  continuaram sendo persistidas, com **zero perda de dado e zero consumo de
  error budget**.
- p95 voltou a 17ms depois do incidente, contra 21ms de linha de base — a
  recuperação foi completa, sem degradação residual.

## O que não funcionou / poderia ser melhor

- **A detecção é ~11x mais lenta que a recuperação** (424s contra 37s). É o
  achado central: o alerta de latência só existe para o caso em que o
  self-heal *não* resolve, mas hoje ele é lento demais para testemunhar o
  incidente comum. Reduzir a janela do `rate` e o `for` (por exemplo
  `rate[2m]` + `for: 2m`) levaria o MTTD para ~3 min, ao custo de mais
  sensibilidade a ruído — ação corretiva nº 6.
- **`SolidaryTechTargetDown` não cobre "réplicas a zero"** — ver "O que o
  ensaio refutou". Lacuna real de cobertura, ação corretiva nº 5.
- **O Alertmanager não pôde ser observado agrupando dois alertas**, já que só
  um disparou. O `group_by` por `service` está configurado e validado com
  `amtool`, mas o cenário não exercitou o agrupamento.
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
| 1 | Executar o ensaio cronometrado e preencher os campos deste documento | detectar | Plataforma | antes da gravação do vídeo | **concluído em 2026-07-25** |
| 2 | Avaliar circuit breaker (ou timeout adaptativo) na validação `donation → ngo` | mitigar | Plataforma | backlog | aberto |
| 3 | Definir error budget de latência (além do de disponibilidade) em `sre-slo.md` | detectar | Plataforma | backlog | aberto |
| 4 | ~~Avaliar webhook GitHub → ArgoCD para reduzir o piso de 3 min do MTTR~~ | — | — | — | **cancelada**: o ensaio mostrou que esse piso não existe (37s medidos). O webhook aceleraria deploys a partir do Git, não a recuperação de drift |
| 5 | Cobrir "réplicas a zero" com uma regra sobre `kube_deployment_status_replicas_available` ou `absent(up{...})` — hoje o `TargetDown` não detecta esse caso | detectar | Plataforma | próximo ciclo | **aberto** (originada pelo ensaio) |
| 6 | Reduzir `rate[5m]`/`for: 5m` do alerta de latência para ~2m, aproximando o MTTD (424s) do MTTR (37s) | detectar | Plataforma | próximo ciclo | **aberto** (originada pelo ensaio) |
| 7 | Roteamento de notificação por e-mail via Workflow do New Relic bloqueado por `MISSING_ENTITLEMENT` no plano free — reavaliar em conta com entitlement ou migrar o roteamento para o receiver `plantao` do Alertmanager | mitigar | Plataforma | backlog | **aberto** (limitação externa) |

## Reprodução (roteiro do ensaio)

O ensaio é automatizado por [`scripts/mttr-drill.sh`](../scripts/mttr-drill.sh),
que cronometra tudo em UTC e grava as evidências. Cronometrar à mão foi
descartado: os eventos que importam acontecem com segundos de diferença e
alguns só aparecem consultando a API do Prometheus.

```bash
# Pré-requisito: envs/primary aplicado + deploy-primary.sh executado,
# Applications Healthy/Synced, `hey` instalado, e uma ONG já cadastrada.
pkill -f port-forward   # túnel apontando para pod morto invalida a medição

# Modo detect: segura o incidente aberto até o alerta acender (mede MTTD real)
NGO_ID=<id> BASELINE_SECS=120 ./scripts/mttr-drill.sh detect 18m 8

# Modo selfheal: sem retenção, mede o laço GitOps puro
NGO_ID=<id> ./scripts/mttr-drill.sh selfheal 12m 8
```

**Concorrência importa.** Com `c=20` a linha de base já sai em ~830ms, acima
do SLO — a carga satura o `db.t4g.micro` e o alerta de latência passa a medir
o gerador de carga, não o incidente. Com `c=8` a base fica em ~20ms. O script
avisa quando a linha de base nasce inválida.

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
