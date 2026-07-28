# Roteiro do vídeo de demonstração

Objetivo: demonstrar **funcionando** cada requisito do edital — a regra de
avaliação é explícita ("não basta configurar"). Cada bloco abaixo traz, na
ordem: **o que aparece na tela**, **o comando ou URL exato**, e **o que
apontar** enquanto fala.

**Duração alvo: 12–15 min.**

> Todos os números citados neste roteiro foram **medidos** contra a AWS real
> em 2026-07-25. As evidências brutas estão em [`evidencias/`](evidencias/) e
> podem ser abertas em tela se a banca pedir.

---

## Painel de acesso (deixe tudo aberto antes de gravar)

### Terminais de port-forward

Abra **um terminal por linha** e deixe rodando o vídeo inteiro. Se algum cair,
a aba do navegador correspondente para de responder.

```bash
kubectl -n argocd       port-forward svc/argocd-server 8080:443
kubectl -n monitoring   port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring   port-forward svc/kube-prometheus-stack-prometheus 9090:9090
kubectl -n monitoring   port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
kubectl -n solidarytech port-forward svc/ngo-service 8081:8081
kubectl -n solidarytech port-forward svc/donation-service 8082:8082
kubectl -n solidarytech port-forward svc/volunteer-service 8083:8083
```

### URLs e credenciais

| O quê | URL | Login |
|---|---|---|
| **ArgoCD** | <https://localhost:8080> | `admin` / comando abaixo (aceite o aviso de certificado) |
| **Grafana** | <http://localhost:3000> | `admin` / comando abaixo |
| **Prometheus — alertas** | <http://localhost:9090/alerts> | — |
| **Prometheus — regras** | <http://localhost:9090/rules> | — |
| **Prometheus — targets** | <http://localhost:9090/targets> | — |
| **Alertmanager** | <http://localhost:9093> | — |
| **Repositório** | <https://github.com/Kaio4816/tech-challenge-fase-5> | — |
| **GitHub Actions** | <https://github.com/Kaio4816/tech-challenge-fase-5/actions> | sua conta GitHub |
| **SonarCloud (org)** | <https://sonarcloud.io/organizations/kaio4816/projects> | login com GitHub |
| **SonarCloud (Hot Path)** | <https://sonarcloud.io/project/overview?id=kaio4816_donation-service> | idem |
| **New Relic** | <https://one.newrelic.com> | conta **8324859** |
| **New Relic — tracing** | <https://one.newrelic.com/distributed-tracing> | filtrar `service.name = donation-service` |
| **New Relic — alertas** | <https://one.newrelic.com/alerts> | policies `SolidaryTech - ...` |
| **New Relic — NRQL** | <https://one.newrelic.com/data-exploration/query-builder> | consultas prontas no bloco 6 |
| **AWS Tag Editor** | <https://us-east-1.console.aws.amazon.com/resource-groups/tag-editor/find-resources> | filtrar `Project = SolidaryTech` |
| **AWS Cost Explorer** | <https://us-east-1.console.aws.amazon.com/cost-management/home#/cost-explorer> | agrupar por tag `CostCenter` |
| **AWS EKS** | <https://us-east-1.console.aws.amazon.com/eks/clusters/solidarytech-primary-eks> | — |

Senhas (rode antes, deixe copiadas):

```bash
# ArgoCD
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Grafana
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

### Checklist de preparação (30–40 min, **não** gravar)

- [ ] `terraform apply` do `envs/primary` — 90 recursos.
- [ ] CI disparada e verde (o ECR nasce vazio a cada apply; sem isso os pods
      ficam em `ImagePullBackOff`).
- [ ] `./scripts/deploy-primary.sh` **com** `NEW_RELIC_LICENSE_KEY` definida.
- [ ] `kubectl -n argocd get applications` → **9 Applications** `Synced`/`Healthy`.
- [ ] Dados de seed criados (1 ONG + doações + 1 voluntário).
- [ ] `hey` e `jq` instalados (`brew install hey jq`) — o `jq` é usado no
      bloco 5 para encadear o `id` da ONG na doação.
- [ ] **Tags de alocação de custo ativadas em Billing** — leva até 24h para o
      Cost Explorer agrupar por tag. Se não deu tempo, use o Tag Editor, que é
      imediato (bloco 8).
- [ ] Abas abertas e logadas conforme a tabela acima.

---

## Bloco 1 — Abertura e arquitetura (1 min)

**Falar**: nome, RM, o que é a SolidaryTech e os 4 objetivos da diretoria
(doações não param, custo controlado, resposta preditiva, SLO/SLA claros).

**Na tela**: [`architecture.md`](architecture.md), o primeiro diagrama Mermaid.
Depois, a raiz do repositório mostrando `apps/`, `infra/`, `gitops/`, `docs/`.

**Apontar**: o `donation-service` no diagrama e a seta dele para o `ngo-service`.

> **Frase-chave**: "o `donation-service` é o Hot Path — tudo que vem a seguir
> gira em torno de manter esse caminho de pé."

## Bloco 2 — Fundação: Docker, Terraform, EKS (2 min)

**Na tela, nesta ordem**:

1. `apps/donation-service/Dockerfile` — apontar **duas** linhas: o
   `FROM golang:1.25-alpine AS builder` e a imagem final `distroless`
   (sem shell dentro do container).
2. `infra/terraform/modules/` — os 7 módulos. Abrir `modules/eks/main.tf` e
   apontar `capacity_type` em **Spot**.
3. Terminal:

```bash
kubectl get nodes -o wide
kubectl -n solidarytech get pods
```

**Apontar**: nós `Ready` e os 3 serviços `Running`.

> **Frase-chave**: "nada aqui foi criado pelo console — cluster, banco, fila e
> tabela saem todos de `terraform apply`."

## Bloco 3 — CI/CD DevSecOps (2 min)

**Na tela**: <https://github.com/Kaio4816/tech-challenge-fase-5/actions>

1. Abrir uma run de **CI - donation-service** — **use o filtro `Event: push`**,
   não simplesmente "a mais recente". Reruns manuais (`workflow_dispatch`) têm
   `Push para ECR` e `Atualizar imagem no GitOps` **cinza/`skipped`** por
   desenho (guarda `github.event_name == 'push'`: rerun manual não empurra
   imagem nem commita bump), e é justamente o fim da esteira que interessa
   aqui. A run disparada no checklist de preparação serve — ela nasce de um
   commit-gatilho real.

   Apontar os **8 jobs verdes**: `Build & Test → SAST (Semgrep) → SonarCloud →
   SCA → Build da imagem → Trivy (imagem) → Push para ECR →
   Atualizar imagem no GitOps`.
2. **Trivy — o portão de segurança da esteira.** Numa run verde a tabela do
   Trivy vem zerada, o que prova que o scan roda, mas **não** que ele bloqueia.
   Mostre as três coisas, nesta ordem:

   a. **O portão**, em `.github/workflows/ci-donation-service.yml` (job
      `scan-image`) — 3 linhas: `severity: HIGH,CRITICAL` (o que conta),
      `exit-code: "1"` (o que **quebra**) e `ignore-unfixed: true` (só CVE com
      correção publicada — bloquear pelo que ninguém pode corrigir só ensina o
      time a ignorar o alerta).

   b. **O log da run verde da `main`**: alvo `donation-service:<sha>` — a
      imagem exata recém-construída — com `0` nas duas camadas (base + binário
      Go), e `debian 12.15` com **4 pacotes**: é a distroless, sem shell.

   c. **A prova do bloqueio** — [PR #1](https://github.com/Kaio4816/tech-challenge-fase-5/pull/1)
      (aberto só como evidência, **não mergear**). Muda só a base da imagem
      final para `alpine:3.10`. Abrir a aba **Checks**:

      | Job | Resultado |
      |---|---|
      | `Build & Test`, `SAST`, `SonarCloud`, `SCA`, `Build da imagem` | ✅ verdes |
      | `Trivy (imagem)` | ❌ `CVE-2021-36159` CRITICAL em `apk-tools`, `fixed 2.10.7-r0` → `Process completed with exit code 1` |
      | `Push para ECR`, `Atualizar imagem no GitOps` | ⏭️ nunca executam (`needs: scan-image`) |

   **Falar**: "o código Go é idêntico ao da `main` — mudou só a imagem base. O
   Trivy achou uma CRITICAL **com correção disponível**, saiu com código 1, e
   os dois jobs seguintes nem chegaram a existir: a imagem vulnerável não chega
   ao registry, muito menos ao cluster."
3. Abrir o job **Push para ECR** e apontar o `configure-aws-credentials`:
   **não existe `AWS_ACCESS_KEY_ID` em lugar nenhum**, a autenticação é OIDC.
4. **SonarCloud — o "SonarQube" do edital.** Comece pela visão da organização,
   <https://sonarcloud.io/organizations/kaio4816/projects>: os **3 projetos**,
   um por microsserviço, todos com **quality gate `Passed`**.

   **Falar**: "o edital pede SonarQube; usei o SonarCloud, que é o mesmo motor
   de análise entregue como serviço — grátis em repositório público e sem um
   servidor para manter. São três projetos porque a chave é montada como
   `<org>_<serviço>` no workflow: análises separadas, um quality gate por
   serviço."

   Depois entre no Hot Path,
   <https://sonarcloud.io/project/overview?id=kaio4816_donation-service>, e
   aponte: **quality gate Passed**, `0 bugs`, `0 vulnerabilities`,
   `3 code smells`, **cobertura 25,3%**.

   > ⚠️ **Não fuja da cobertura baixa** — a banca vai ver. Assuma:
   > "cobertura de 25% no `donation-service` contra ~80% nos dois serviços
   > Python. O teste cobre a regra de negócio da doação; o que está descoberto
   > é integração — Postgres, SQS e a chamada ao `ngo-service` — que eu cubro
   > com o `/ready` e com os SLOs em produção, não com teste unitário. É uma
   > dívida consciente, não um esquecimento."

   > ⚠️ Nos **dois serviços Python** aparecem `3 vulnerabilities` cada, e são
   > as mesmas: 2× `Dockerfile:5` (`pip install` sem `--only-binary :all:` e
   > sem lock de versões resolvidas) e 1× `app.py:17` (regra S4502, "CSRF
   > desabilitado" — falso positivo: são APIs REST sem sessão por cookie). Se
   > perguntarem, é isso; nenhuma é achado de código.
5. **O commit que o pipeline escreveu** —
   <https://github.com/Kaio4816/tech-challenge-fase-5/commit/c0149ca>

   Percurso do cursor: título do commit → **autor** → o arquivo alterado →
   a linha `newTag`.

   **Falar**: "esse é o último passo da esteira, e é o mais importante para
   entender o desenho: o pipeline **não** faz deploy. Ele faz *um commit*.
   Repare no autor — `github-actions[bot]`. Nenhuma pessoa digitou isso.
   Repare no tamanho: **um arquivo, uma linha**. É o `newTag` do
   `kustomization.yaml` do overlay `primary`, ou seja, a esteira trocou a tag
   da imagem do `donation-service` para o SHA que ela acabou de construir,
   escanear e publicar no ECR.
   E repare no `[skip ci]` no fim da mensagem: sem ele, esse commit dispararia
   a esteira de novo, que faria outro commit, e assim por diante — laço
   infinito. É um detalhe pequeno que só aparece quando você roda de verdade."

   Se sobrar tempo, abrir o histórico só desse arquivo — uma coluna inteira de
   commits do bot mostra que isso é rotina, não um caso isolado:
   <https://github.com/Kaio4816/tech-challenge-fase-5/commits/main/gitops/workloads/overlays/primary/donation-service/kustomization.yaml>

**Fechamento do bloco** (dizer olhando para o SHA na tela, é a deixa para o
bloco 4):

> "Então o que a esteira entrega não é software rodando — é **estado
> declarado**. A imagem está no ECR, a intenção está no Git, e ninguém tocou
> no cluster até aqui. Guarde esse SHA: `7504328f`. Daqui a pouco, no ArgoCD,
> ele vai aparecer como a revisão sincronizada — é ali que o deploy realmente
> acontece."

> **Frase-chave**: "o pipeline não faz deploy — ele altera o Git. Quem faz
> deploy é o ArgoCD."

## Bloco 4 — GitOps ponta a ponta (2 min)

**Na tela**: <https://localhost:8080> (ArgoCD)

1. Vista de aplicações: `solidarytech-root` como app-of-apps e as
   **9 Applications** `Healthy`/`Synced`. Clicar em `solidarytech-root` para
   mostrar que ele gera as demais.
2. **Self-heal ao vivo** — rápido e confiável:

```bash
kubectl -n solidarytech scale deploy/volunteer-service --replicas=3
kubectl -n solidarytech get pods -l app.kubernetes.io/name=volunteer-service -w
```

**Narrar**: os 3 pods sobem, o ArgoCD marca `OutOfSync` e derruba de volta para
1 — **sem ninguém digitar nada**. Esse laço foi medido em **37 segundos** no
ensaio de MTTR.

> **Frase-chave**: "o estado desejado está no Git; qualquer divergência é
> revertida sozinha."

## Bloco 5 — Fluxo de negócio real (1 min)

**Abrir dizendo** (enquanto limpa o terminal): "até aqui mostrei esteira e
plataforma. Agora o produto: os três microsserviços fazendo o que a ONG
precisa que eles façam. São três chamadas, e cada uma toca uma tecnologia
diferente de persistência."

```bash
# 1) criar uma ONG — o id volta na variável, não precisa digitar nada depois
NGO_ID=$(curl -s -X POST localhost:8081/ngos -H 'Content-Type: application/json' \
  -d '{"name":"ONG Demo","email":"demo@ong.org","cause":"Educacao","city":"Sao Paulo"}' \
  | jq -r .id)
echo "ONG criada com id $NGO_ID"
```

> **Falar**: "primeira: cadastro de ONG, no `ngo-service`, em Flask. Grava no
> Postgres do RDS. Estou guardando numa variável o `id` que ele devolve,
> porque a próxima chamada depende dele."

> ⚠️ **Não use `"ngo_id": 1` fixo.** A tabela já tem os seeds do `init.sql` e
> o `SERIAL` nunca recua, então a ONG criada na gravação **não** será a de id
> 1 — a doação iria para outra ONG, não para a que apareceu na tela. Daí o
> encadeamento por variável.

```bash
# 2) doação usando esse id — Hot Path: valida o ngo_id chamando o ngo-service
curl -s -X POST localhost:8082/donations -H 'Content-Type: application/json' \
  -d "{\"ngo_id\": $NGO_ID, \"amount\": 250.00, \"donor_name\": \"Doador Demo\"}"
```

> **Falar**: "segunda: a doação. Este é o **Hot Path**, em Go, e é o único
> serviço que fala com outro — antes de gravar, ele chama o `ngo-service` para
> validar se essa ONG existe. Repare no `201 Created`: a doação foi para o
> Postgres e, **depois do commit**, um evento foi publicado no SQS. Essa ordem
> é deliberada e volta no bloco de DR: a doação existe antes da notificação,
> então perder a fila num failover não perde doação."

```bash
# 3) voluntário -> DynamoDB
curl -s -X POST localhost:8083/volunteers -H 'Content-Type: application/json' \
  -d "{\"name\":\"Voluntario Demo\",\"email\":\"vol@demo.org\",\"ngo_id\": $NGO_ID}"
```

> **Falar**: "terceira: voluntário, no `volunteer-service`, também Flask, mas
> gravando em **DynamoDB** — banco diferente, para mostrar que a plataforma
> não assume um único modelo de persistência."

> ⚠️ `POST /volunteers` exige **`ngo_id`** — mandar `skill` no lugar devolve
> `400 Campos obrigatórios ausentes`. Teste antes de gravar.

> ⚠️ **`email` da ONG é `UNIQUE`.** Se você ensaiar este bloco e gravar
> depois, o segundo `POST /ngos` com `demo@ong.org` devolve
> **`409 E-mail já cadastrado`** e o `NGO_ID` vira `null`, derrubando as duas
> chamadas seguintes. Entre uma tomada e outra, ou troque o e-mail, ou limpe
> os registros (não há endpoint `DELETE` — só os três `POST`/`GET`):
>
> ```bash
> cd infra/terraform/envs/primary
> RDS_HOST="$(terraform output -raw rds_endpoint)"; RDS_HOST="${RDS_HOST%%:*}"
> docker run --rm -e PGPASSWORD="$(terraform output -raw rds_master_password)" \
>   -e PGCONNECT_TIMEOUT=10 postgres:16-alpine \
>   psql -h "$RDS_HOST" -U "$(terraform output -raw rds_master_username)" \
>   -d ngo_db -c "DELETE FROM ngos WHERE email = 'demo@ong.org';"
> ```

**Mostrar a persistência real** (prova de IRSA — nenhum pod tem access key):

```bash
aws dynamodb scan --table-name SolidaryTechVolunteers --region us-east-1 \
  --query 'Items[].{nome:name.S,email:email.S}'
```

> **Falar**: "e aqui está o voluntário, consultado direto na AWS — não é a
> aplicação me contando que gravou, é o DynamoDB confirmando. E o ponto de
> segurança: para escrever isso, o pod **não** tem chave de acesso nenhuma.
> Nem em variável de ambiente, nem em Secret. Ele assume um role da AWS pela
> identidade da própria ServiceAccount do Kubernetes — é o IRSA, criado pelo
> Terraform no módulo `irsa`. Se alguém invadir o container, não há credencial
> para roubar; e o role só permite escrever nessa tabela."

> **Frase-chave**: "o pod assume um role via IRSA — não existe credencial
> estática em lugar nenhum do cluster."

## Bloco 6 — Observabilidade e SRE (3 min)

> ⏱ **Dispare o ensaio de MTTR num terminal separado ANTES de começar este
> bloco** — a detecção leva ~7 min e você volta a ele no bloco 7:
> ```bash
> NGO_ID=1 BASELINE_SECS=120 ./scripts/mttr-drill.sh detect 18m 8
> ```

**Na tela, nesta ordem**:

1. [`sre-slo.md`](sre-slo.md) — os 2 SLIs, SLO **99,9%**, SLA **99,5%** e o
   error budget de **43,2 min/30d**.

   > **Falar**: "SRE começa por decidir o que significa 'funcionando'. Defini
   > dois indicadores para o Hot Path, medidos das próprias métricas do
   > serviço: **disponibilidade** — proporção de respostas não-5xx em
   > `POST /donations` — e **latência**, o p95 dessa mesma rota.
   >
   > O SLA com as ONGs parceiras é 99,5% ao mês. Mas o SLO interno é
   > **99,9%** — mais rígido de propósito. A folga entre os dois é o tempo que
   > a engenharia tem para agir antes de descumprir contrato.
   >
   > E 99,9% em 30 dias vira um número muito concreto: **43,2 minutos**. Esse
   > é o **error budget** — quanto o serviço pode ficar ruim no mês sem violar
   > o SLO. Não é uma meta de perfeição; é um orçamento, e orçamento existe
   > para ser gasto. Enquanto sobra budget, dá para arriscar deploy; quando
   > acaba, a prioridade vira confiabilidade."

2. **Grafana** <http://localhost:3000> → dashboard
   *"SolidaryTech - SRE Golden Metrics & SLO"*, já sob a carga do ensaio.

   > **Falar**: "esse dashboard é versionado como código — é um ConfigMap no
   > Git, aplicado pelo ArgoCD, não algo que eu desenhei clicando na UI. Se o
   > cluster for destruído e recriado, ele volta idêntico.
   >
   > Estão aqui as **golden metrics**: throughput — e repare que ele está
   > subindo, porque tem um teste de carga rodando neste momento —, taxa de
   > erro, e as latências p50, p95 e p99. Os três percentis juntos porque a
   > média mente: dá para ter média ótima e 5% dos doadores esperando dois
   > segundos.
   >
   > E este gauge é o que traduz tudo para linguagem de negócio: **error
   > budget restante**. Não 'o serviço está bom'; e sim 'sobram tantos minutos
   > de falha este mês'."

3. **Prometheus** <http://localhost:9090/rules> → os 3 grupos do projeto:
   `donation-service.slo.recording`, `donation-service.slo.alerting` e
   `solidarytech.platform.alerting`.

   > **Falar**: "as regras que alimentam aquilo. As de **recording**
   > pré-calculam a taxa de erro em quatro janelas de tempo; as de
   > **alerting** implementam *multi-window, multi-burn-rate*, que é a prática
   > recomendada pelo Google SRE: um alerta crítico quando o orçamento queima
   > a **14,4×** o ritmo sustentável — nesse ritmo os 43 minutos do mês
   > acabam em dois dias — e um alerta de aviso a **6×**. Duas janelas em cada
   > um, curta e longa, para não gritar por um pico de 30 segundos e ao mesmo
   > tempo não demorar meia hora para perceber uma queda real."

4. **New Relic — distributed tracing**:
   <https://one.newrelic.com/distributed-tracing> → filtrar
   `service.name = donation-service`, abrir um trace de `POST /donations` e
   mostrar o span filho `GET /ngos/<int:ngo_id>` **rodando no `ngo-service`**:
   dois serviços num único trace.

   > **Falar**: "métrica diz *que* está lento; trace diz **onde**. Este é um
   > `POST /donations` real. Repare na hierarquia: o span pai é o Go, e dentro
   > dele há um span filho que está executando **no outro serviço**, o
   > `ngo-service`, em Python. Dois processos, duas linguagens, dois pods —
   > um único trace, porque o contexto viaja no cabeçalho HTTP.
   >
   > Isso não sai de graça: o OpenTelemetry em Go tem o propagador global
   > desligado por padrão, e sem `SetTextMapPropagator` o cabeçalho
   > `traceparent` não é injetado. O sintoma engana, porque a telemetria
   > 'funciona' — chegam spans, aparecem os dois serviços — só que em traces
   > separados. Foi um bug real que só apareceu olhando esta tela."

   Alternativa por consulta, no query builder
   (<https://one.newrelic.com/data-exploration/query-builder>):

   ```sql
   SELECT uniqueCount(service.name) AS servicos, count(*) AS spans
   FROM Span WHERE name IN ('POST /donations','HTTP GET','GET /ngos/<int:ngo_id>')
   FACET trace.id SINCE 30 minutes ago
   ```
   Cada linha deve mostrar **2 serviços e 3 spans**.

5. **Logs**: Grafana → *Explore* → datasource **Loki** → query
   `{namespace="solidarytech"}`.

   > **Falar**: "e o terceiro pilar: logs dos três serviços centralizados no
   > Loki, coletados por um DaemonSet do Promtail. Métrica, trace e log na
   > mesma ferramenta — quem está de plantão não troca de aba no meio de um
   > incidente."

> **Frase-chave**: "o SLO é mais rígido que o SLA de propósito — a folga é o
> tempo que temos para agir antes de descumprir o contrato com as ONGs."

## Bloco 7 — MTTR: incidente do início ao fim (2,5 min) ⭐

Volte ao terminal do ensaio disparado no bloco 6.

**Na tela**: o terminal do `mttr-drill.sh` + <http://localhost:9090/alerts>.

**Abrir dizendo**: "tudo que mostrei até agora está de pé e saudável. Agora eu
quebro de propósito, com cronômetro, e mostro o ciclo inteiro: falha →
detecção → alerta → recuperação → post-mortem. O incidente é realista: vou
derrubar o `ngo-service`, a dependência do Hot Path."

**Narrar a linha do tempo conforme ela aparece**:

| Momento | O que apontar | O que dizer |
|---|---|---|
| `T0_INICIO_IMPACTO` | o `ngo-service` foi a zero réplicas | "aqui começa o impacto — a dependência do Hot Path acabou de sumir" |
| `DEGRADACAO_P95` (~+54s) | p95 salta de **21ms para ~1000ms** — mostrar no Grafana | "54 segundos depois o p95 salta de 21 milissegundos para cerca de 1 segundo — o Hot Path está esperando o timeout de 2s da dependência" |
| — | **nenhuma doação falhou**: `curl -s localhost:8082/donations \| tail -c 300` continua gravando | "e este é o ponto: **nenhuma doação falhou**. A validação é *fail-open* — só um 404 explícito rejeita. A dependência caiu, e a doação continua sendo gravada. A regra da diretoria era 'as doações não podem parar', e isso vale também para uma falha interna nossa" |
| `ALERTA_FIRING` (~+7min) | `DonationServiceHighLatencyP95` fica vermelho em `/alerts` | "**424 segundos** — 7 minutos — para o alerta sair de `Pending` para `Firing`. Esse é o MTTD, o tempo de detecção" |
| `T3_RECUPERADO` | ArgoCD restaura o serviço — **37s** após ser liberado | "e agora a recuperação: eu não fiz nada. `replicas: 1` está no Git, o ArgoCD viu a divergência e restaurou. **37 segundos**" |
| `T4_FIM_IMPACTO` | alertas resolvidos, p95 volta a ~17ms | "alerta resolvido, p95 de volta a 17 milissegundos" |

**Os três pontos que a banca precisa ouvir** — dizer explicitamente, são o
conteúdo do bloco:

1. **Só o alerta de latência disparou** — nenhum de erro, nenhum de burn rate.

   > **Falar**: "repare no que **não** aconteceu: nenhum alerta de erro,
   > nenhum de burn rate. Porque o fail-open transformou indisponibilidade da
   > dependência em **latência, não em erro** — e como o error budget está
   > atrelado ao SLI de disponibilidade, ele saiu **intacto** do incidente.
   > Uma consequência prática que muda a triagem: quem for investigar isso
   > procurando 5xx vai procurar no lugar errado. Está documentado no runbook
   > exatamente por isso."

2. **MTTD 424s contra MTTR 37s** — a recuperação é ~11× mais rápida que a
   detecção.

   > **Falar**: "e aqui está o achado mais interessante do ensaio, que é
   > desconfortável e por isso vale mais: detectar levou 424 segundos;
   > recuperar levou 37. A recuperação é **onze vezes mais rápida que a
   > detecção**. O que isso significa é que, se eu não segurasse o incidente
   > artificialmente, o sistema **se curaria antes de perceber que estava
   > doente** — e esse modo de falha seria praticamente invisível para o
   > alerting. É ótimo para o usuário e péssimo para quem opera: falha que não
   > deixa rastro é falha que se repete."

3. Isso é **lacuna real revelada pelo ensaio**, registrada como ação corretiva
   em [`postmortem-mttr-demo.md`](postmortem-mttr-demo.md).

   > **Falar**: "não descobri isso no papel — descobri rodando, e virou ação
   > corretiva no post-mortem, com dono. Aliás, o ensaio **refutou três
   > previsões** que eu tinha escrito antes: eu achava que o alerta de
   > `TargetDown` cobriria réplicas a zero, e não cobre — com zero réplicas a
   > série `up` simplesmente **some**, e ausência de série não satisfaz
   > `up == 0`. Eu achava que o ArgoCD teria um piso de 3 minutos pelo
   > intervalo de reconciliação, e não tem — o self-heal é por watch, deu 37
   > segundos. Ensaio que só confirma o que você já achava não estava medindo
   > nada."

> ⚠️ **Não prometa o que não vai acontecer**: `SolidaryTechTargetDown` **não**
> dispara neste cenário (com 0 réplicas a série `up` some, e `up == 0` não casa
> com série ausente), e **não haverá e-mail do New Relic** — o Workflow não pôde
> ser criado no plano free. Os dois estão explicados no post-mortem; citar como
> achado é mais forte do que omitir e ser perguntado.

> **Frase-chave**: "detectamos em 7 minutos e recuperamos em 37 segundos, sem
> intervenção humana — e o ensaio mostrou que o gargalo é a detecção, não a
> correção."

## Bloco 8 — FinOps (1,5 min)

**Na tela**:

**Abrir dizendo**: "FinOps aqui não é enfeite. O cliente é uma ONG: cada dólar
que vai para infraestrutura é um dólar que não vira projeto social. Então
custo é requisito, não consequência."

1. `infra/terraform/envs/primary/providers.tf` — o bloco `default_tags` com
   `Project`, `Environment` e `CostCenter`.

   > **Falar**: "governança de custo começa por saber de quem é a conta. Estas
   > três tags — `Project`, `Environment` e `CostCenter` — estão em
   > `default_tags` do provider AWS, o que significa que **todo** recurso que
   > o Terraform criar nasce etiquetado, sem ninguém precisar lembrar. Não
   > existe caminho para criar recurso sem tag, porque não existe caminho para
   > criar recurso fora do Terraform."

2. Terminal:

```bash
aws resourcegroupstaggingapi get-resources --region us-east-1 \
  --tag-filters Key=Project,Values=SolidaryTech \
  --query 'length(ResourceTagMappingList)'
```

   > **Falar**: "e a prova: essa é a quantidade de recursos que a AWS
   > reconhece hoje como pertencentes a este projeto, consultada por tag."

3. **AWS Tag Editor** (rende melhor em vídeo que o terminal):
   <https://us-east-1.console.aws.amazon.com/resource-groups/tag-editor/find-resources>
   → região `us-east-1`, todos os tipos, tag `Project = SolidaryTech`.

   > **Falar**: "o mesmo dado no console, que é mais fácil de ler: cluster,
   > banco, fila, tabela, repositórios, rede — tudo com a mesma etiqueta, e
   > portanto tudo rastreável no Cost Explorer por centro de custo.
   > Honestidade: **alguns tipos de recurso a AWS simplesmente não permite
   > etiquetar** — associação de route table, config de replicação do ECR,
   > provider OIDC. Não é falha de cobertura, é limitação da plataforma, e
   > está documentado."

4. [`finops-forecast.md`](finops-forecast.md) — a tabela de custo e as
   economias.

   > **Falar**: "o forecast é linha a linha, com preço unitário: **cerca de
   > US$ 150 por mês** se isso ficasse de pé 24 por 7. O maior item nem é
   > computação — são os **US$ 73 do control plane do EKS**, que é preço fixo
   > da AWS, seguido de US$ 35 do NAT Gateway.
   >
   > E aqui as decisões de engenharia que derrubaram esse número: nós em
   > **Spot** em vez de on-demand, −70% na conta de EC2; **um** NAT Gateway em
   > vez de um por zona, −US$ 33; **uma** instância RDS com dois bancos em vez
   > de duas instâncias, metade do custo; **nenhum load balancer** — as demos
   > usam port-forward, o que economiza US$ 20 por mês *e* evita um LB órfão
   > travando o destroy; e a maior de todas: o ambiente de **DR criado sob
   > demanda**, que elimina 100% do custo ocioso de um standby permanente —
   > US$ 145 por mês que simplesmente não existem.
   >
   > Um item que quase todo forecast esquece e este inclui: **CloudWatch Logs
   > do control plane do EKS**, uns US$ 2,50 por mês que aparecem na fatura
   > sem ninguém ter pedido."

5. Rightsizing, com a carga ainda rodando:

```bash
kubectl -n solidarytech top pods
```
   Comparar com os `requests`/`limits` em `gitops/workloads/base/`.

   > **Falar**: "e rightsizing com dado, não com chute: este é o consumo real
   > dos pods **sob carga**, para comparar com os `requests` e `limits`
   > declarados. Requests altos demais desperdiçam nó reservando o que não se
   > usa; baixos demais fazem o Kubernetes matar o pod na hora errada.
   >
   > A propósito de dimensionamento, o achado mais contraintuitivo deste
   > projeto: o limite de escala do cluster **não** era CPU nem memória — era
   > **pods por nó**. O CNI da AWS aloca IPs por interface de rede, e um
   > `t3.medium` só comporta 17 pods. Bati o teto com CPU em 50% e memória em
   > 45%: qualquer painel de recursos mostraria o cluster folgado, e os pods
   > ficavam `Pending`."

> Se o Cost Explorer ainda não agrupar por tag, **diga isso em voz alta**: a
> ativação como *cost allocation tag* leva até 24h. O Tag Editor prova a
> cobertura de imediato.

> **Frase-chave**: "cada linha dessa conta tem uma decisão de engenharia atrás."

## Bloco 9 — ITSM e AIOps (1,5 min)

**Na tela**:

1. [`itsm-incident-flow.md`](itsm-incident-flow.md) — o diagrama dos 5
   estágios. Percurso do cursor: caixas 1 → 2 → 3 → 4 → 5, e **por último** a
   seta pontilhada para "Sem incidente formal".

   > **Falar**: "o incidente que vocês acabaram de ver não é um evento solto:
   > ele percorre um processo, e cada caixa aqui aponta para um artefato que
   > existe no repositório. **Detecção** em três camadas redundantes:
   > Prometheus pega violação de contrato, New Relic pega desvio do normal, e
   > os probes do Kubernetes pegam pod morto em segundos. **Alerta**:
   > Alertmanager agrupa e deduplica. **Tratamento**: runbook com árvore de
   > decisão. **Post-mortem** blameless em 48 horas. E **comunicação**, com
   > modelos prontos de e-mail para diretoria e para as ONGs.
   >
   > Mas a seta mais importante do diagrama é esta pontilhada:
   > **a maior parte das falhas nunca vira incidente formal**. Probe,
   > self-heal e HPA resolvem sozinhos. A forma mais eficaz de baixar MTTR não
   > é responder mais rápido — é fazer com que não haja o que responder."

2. `infra/terraform/newrelic/main.tf` — as condições `type = "baseline"`:
   **anomaly detection como código**, limiar aprendido em vez de fixo.

   > **Falar**: "AIOps aqui tem significado concreto. Estas duas condições são
   > `type = "baseline"`: em vez de eu dizer 'alerte acima de 300
   > milissegundos', o New Relic **aprende** o comportamento normal do serviço
   > e dispara quando ele se desvia. É a diferença entre detecção reativa e
   > preditiva: um alerta de burn rate só existe depois que já houve erro; um
   > baseline dispara quando o comportamento *muda*, mesmo sem erro nenhum —
   > por exemplo, se as doações simplesmente pararem de chegar num horário em
   > que sempre chegam. Nenhum alerta de erro pegaria isso, porque não há
   > erro.
   >
   > E repare que isso é **Terraform**, não configuração clicada: o edital
   > proíbe criar coisa pelo console, e alerta configurado na mão é alerta que
   > se perde no próximo ambiente."

3. **New Relic** <https://one.newrelic.com/alerts> → as 2 policies
   (`SolidaryTech - donation-service (Hot Path)` e
   `SolidaryTech - plataforma (Kubernetes)`) com as 5 condições.

   > **Falar**: "as mesmas policies aplicadas na conta real: uma para o Hot
   > Path, outra para a plataforma Kubernetes, com cinco condições no total —
   > três de limiar fixo e duas de baseline. E uma limitação declarada: o
   > roteamento automático para e-mail, o *Workflow*, é bloqueado no plano
   > gratuito — a API responde `MISSING_ENTITLEMENT`. O código está escrito e
   > revisado; o que falta é entitlement de plano, não implementação."

4. **Alertmanager** <http://localhost:9093> → o agrupamento por `service` e a
   rota do `Watchdog` para o receiver nulo.

   > **Falar**: "do lado do Prometheus, o Alertmanager cuida do que separa um
   > sistema de alertas útil de um que ninguém lê. Agrupamento por serviço: um
   > deploy ruim que derruba as duas réplicas do `donation-service` é **um**
   > incidente, não dois. Regra de inibição: um alerta crítico silencia o
   > aviso do mesmo serviço, porque os dois vêm do mesmo sintoma. E o
   > `Watchdog`, que dispara sempre — é o alerta que prova que o pipeline de
   > alertas está vivo — vai para um receiver nulo, para nunca notificar
   > ninguém. Essa configuração foi validada com o `amtool` oficial."

5. [`postmortem-mttr-demo.md`](postmortem-mttr-demo.md) — a seção **"O que o
   ensaio refutou"** e a tabela de ações corretivas.

   > **Falar**: "e o ciclo fecha aqui: o post-mortem do incidente que vocês
   > viram acontecer. Blameless, com os cinco porquês, os tempos medidos, e —
   > o que mais importa — uma tabela de ações corretivas **com dono**. Um
   > post-mortem sem commit associado não fechou nada; por isso a última seta
   > do diagrama volta para a detecção. Ação corretiva vira código."

> **Frase-chave**: "detecção preditiva é o limiar aprendido, não o limiar fixo:
> a condição baseline dispara quando o comportamento muda, antes de o SLO ser
> violado."

## Bloco 10 — Disaster Recovery (2 min)

Executar o DR ao vivo custa ~25 min de RTO — **apresente o ensaio registrado**,
que é evidência igualmente válida e cabe no tempo.

**Na tela**:

**Abrir dizendo**: "o objetivo da diretoria era 'mesmo que a nuvem falhe, as
doações não podem parar'. Falha de região é o pior caso, e é o que este plano
cobre. Executar ao vivo levaria 25 minutos, então apresento o **ensaio
registrado** — que foi executado de verdade contra a conta AWS, com dados
reais."

1. [`dr-plan.md`](dr-plan.md) — Warm Standby (Opção B), **RPO ≤ 1h**,
   **RTO alvo 1h**, e a tabela por tipo de dado.

   > **Falar**: "escolhi a **opção B do edital**, warm standby por Terraform
   > modularizado: `us-east-2` usa exatamente os mesmos módulos de
   > `us-east-1`, mas o ambiente **não existe** no dia a dia — ele é criado
   > sob demanda. É a decisão de FinOps do bloco anterior: standby permanente
   > custaria US$ 145 por mês parado, esperando um desastre que talvez nunca
   > venha.
   >
   > E os dois números que definem qualquer plano de continuidade: **RPO**, o
   > quanto se aceita perder de dado — aqui **até 1 hora**; e **RTO**, o
   > quanto se aceita ficar fora — alvo de **1 hora**.
   >
   > Esta tabela é a parte que costuma faltar nos planos: **cada tipo de dado
   > tem uma estratégia diferente**. O Postgres vai por snapshot copiado entre
   > regiões no momento da ativação — não uma cópia periódica velha, o que é
   > justamente o que sustenta o RPO de 1 hora. O DynamoDB é Global Table,
   > replicação contínua da AWS, RPO praticamente zero. As imagens já estão
   > replicadas no ECR antes de qualquer desastre. E a fila SQS é recriada
   > vazia — perda **aceita e declarada**: perde-se notificação em trânsito,
   > não doação, porque a doação é gravada no banco antes de a mensagem ser
   > publicada."

2. `scripts/activate-dr.sh` — mostrar que é **um comando** e apontar as 4
   etapas descritas no cabeçalho.

   > **Falar**: "e o plano é executável, não um documento de gaveta: **um
   > comando**. Ele tira um snapshot fresco do banco, copia para a outra
   > região, roda `terraform apply` no ambiente de DR e sobe o ArgoCD com o
   > overlay `dr`. Quem estiver de plantão às 3 da manhã não precisa lembrar
   > de quatro procedimentos — precisa rodar um script."

3. A seção **"Resultado do ensaio"** do `dr-plan.md`: **RTO medido 24min23s** e
   a prova de RPO — as doações do `us-east-1` retornando íntegras no
   `us-east-2`.

   > **Falar**: "e aqui o que separa 'plano escrito' de 'plano testado'.
   > Executei o ensaio completo: subi o primário, criei uma ONG e duas doações
   > reais, simulei a perda da região, rodei o script e cronometrei.
   >
   > **RTO medido: 24 minutos e 23 segundos**, contra um alvo de 1 hora. A
   > etapa mais lenta é a criação do cluster EKS, uns 15 a 20 minutos — não há
   > o que otimizar aí sem pagar por standby permanente.
   >
   > E a prova de RPO, que é o que realmente importa para uma ONG: um
   > `GET /donations` na região de contingência devolveu **as duas doações
   > criadas na região primária**, com o mesmo `id`, o mesmo valor e o mesmo
   > `created_at`. Nenhum dado transacional perdido.
   >
   > Uma limitação que declaro em vez de esconder: o script lê o `terraform
   > output` do primário, cujo state fica em `us-east-1`. Numa falha *total*
   > da região, isso seria um ponto cego — por isso existe um override por
   > variável de ambiente que pula essa leitura. Replicar o bucket de state
   > resolveria de vez, e foi descartado por custo e complexidade para o
   > escopo deste hackathon."

> **Frase-chave**: "as duas doações criadas no `us-east-1` aparecem no
> `us-east-2` com o mesmo `id` e `created_at` — nenhum dado transacional
> perdido."

## Bloco 11 — Encerramento (30 s)

**Na tela**: `terraform destroy` iniciando.

> **Falar**: "encerro derrubando tudo — e isso é parte da demonstração, não o
> fim dela. Tudo que vocês viram custa cerca de **20 centavos de dólar por
> hora** enquanto está de pé, e some inteiro com um comando. É essa
> propriedade que torna o DR sob demanda viável e a conta pagável por uma ONG:
> infraestrutura que é **código**, não patrimônio.
>
> Recapitulando o que foi demonstrado funcionando: três microsserviços
> conteinerizados rodando em EKS; toda a infraestrutura em Terraform, nada
> pelo console; esteira DevSecOps com SAST, SCA, análise de qualidade e
> bloqueio real por vulnerabilidade de imagem; entrega contínua por GitOps com
> self-heal; observabilidade com métricas, logs e tracing distribuído; SLO,
> error budget e um incidente cronometrado do início ao post-mortem; FinOps
> com tags, forecast e rightsizing; e um plano de continuidade **ensaiado**,
> com RTO e RPO medidos.
>
> Duas pendências que declaro em vez de omitir: o **Workflow do New Relic** —
> o roteamento automático de alerta para e-mail — é bloqueado pelo plano
> gratuito, com a API respondendo `MISSING_ENTITLEMENT`; o código está pronto,
> falta entitlement. E as **ações corretivas 5, 6 e 7** do post-mortem seguem
> abertas, incluindo a lacuna de detecção que o próprio ensaio revelou. Achei
> mais honesto entregar o problema documentado do que fingir que não existe.
>
> Todo o código, os documentos e as evidências brutas estão no repositório.
> Obrigado."

> **Frase-chave**: "a infraestrutura inteira sobe e desce por comando — é isso
> que torna o DR sob demanda viável e a conta pagável por uma ONG."

---

## Dicas de gravação

- **Terminal grande** (fonte ≥ 16pt): comando ilegível não é evidência.
- `clear` antes de cada bloco de terminal — rolagem antiga confunde.
- Ao abrir um arquivo, aponte **as 2 ou 3 linhas que importam**.
- Quando algo demorar (sync, alerta), **continue narrando o porquê** em vez de
  ficar em silêncio.
- Se algo falhar ao vivo, **não corte**: diagnosticar em tempo real é
  exatamente a competência avaliada em SRE.
- Os port-forwards caem quando o pod é recriado — no bloco 7 o `ngo-service`
  **é** recriado, então o túnel da 8081 vai cair. É esperado; reabra se
  precisar dele depois.

## Mapa vídeo → requisitos do edital

| Bloco | Requisito coberto |
|---|---|
| 2 | Docker, Kubernetes, Terraform (cluster/banco/mensageria/rede) |
| 3 | CI/CD, DevSecOps (build, testes, SAST, SCA, Trivy, SonarQube-equivalente) |
| 4 | GitOps |
| 5 | funcionamento real dos 3 microsserviços |
| 6 | Observabilidade (Prometheus/Grafana/Loki/OTel + New Relic + tracing), SLI/SLO/SLA, dashboard, error budget |
| 7 | MTTR |
| 8 | FinOps (tags, forecast, rightsizing, otimização) |
| 9 | AIOps + ITSM (ciclo completo do incidente) |
| 10 | Plano de Continuidade, RTO/RPO, DR Opção B |
