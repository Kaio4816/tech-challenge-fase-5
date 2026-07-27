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
- [ ] `hey` instalado (`brew install hey`).
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

1. Abrir o run mais recente de **CI - donation-service**. Apontar os **8 jobs
   verdes**: `Build & Test → SAST (Semgrep) → SonarCloud → SCA →
   Build da imagem → Trivy (imagem) → Push para ECR → Atualizar imagem no GitOps`.
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
4. SonarCloud: <https://sonarcloud.io/project/overview?id=kaio4816_donation-service>
5. No histórico do repo, o commit
   `chore(gitops): bump donation-service para <sha> [skip ci]`.

**Apontar**: esse commit foi feito **pelo pipeline**, não por uma pessoa.

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

```bash
# 1) criar uma ONG (guarde o "id" retornado)
curl -s -X POST localhost:8081/ngos -H 'Content-Type: application/json' \
  -d '{"name":"ONG Demo","email":"demo@ong.org","cause":"Educacao","city":"Sao Paulo"}'

# 2) doação usando esse id — Hot Path: valida o ngo_id chamando o ngo-service
curl -s -X POST localhost:8082/donations -H 'Content-Type: application/json' \
  -d '{"ngo_id": 1, "amount": 250.00, "donor_name": "Doador Demo"}'

# 3) voluntário -> DynamoDB
curl -s -X POST localhost:8083/volunteers -H 'Content-Type: application/json' \
  -d '{"name":"Voluntario Demo","email":"vol@demo.org","ngo_id": 1}'
```

> ⚠️ `POST /volunteers` exige **`ngo_id`** — mandar `skill` no lugar devolve
> `400 Campos obrigatórios ausentes`. Teste antes de gravar.

**Mostrar a persistência real** (prova de IRSA — nenhum pod tem access key):

```bash
aws dynamodb scan --table-name SolidaryTechVolunteers --region us-east-1 \
  --query 'Items[].{nome:name.S,email:email.S}'
```

> **Frase-chave**: "o pod assume um role via IRSA — não existe credencial
> estática em lugar nenhum do cluster."

## Bloco 6 — Observabilidade e SRE (3 min)

> ⏱ **Dispare o ensaio de MTTR num terminal separado ANTES de começar este
> bloco** — a detecção leva ~7 min e você volta a ele no bloco 7:
> ```bash
> NGO_ID=1 BASELINE_SECS=120 ./scripts/mttr-drill.sh detect 18m 8
> ```

**Na tela, nesta ordem**:

1. [`sre-slo.md`](sre-slo.md) — apontar os 2 SLIs, SLO **99,9%**, SLA **99,5%**
   e o error budget de **43,2 min/30d**.
2. **Grafana** <http://localhost:3000> → dashboard
   *"SolidaryTech - SRE Golden Metrics & SLO"*, já sob a carga do ensaio.
   Apontar: throughput, taxa de erro, **p50/p95/p99** e o burn rate.
3. **Prometheus** <http://localhost:9090/rules> → os 3 grupos do projeto:
   `donation-service.slo.recording`, `donation-service.slo.alerting` e
   `solidarytech.platform.alerting`.
4. **New Relic — distributed tracing**:
   <https://one.newrelic.com/distributed-tracing> → filtrar
   `service.name = donation-service`, abrir um trace de `POST /donations` e
   mostrar o span filho `GET /ngos/<int:ngo_id>` **rodando no `ngo-service`**:
   dois serviços num único trace.

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

> **Frase-chave**: "o SLO é mais rígido que o SLA de propósito — a folga é o
> tempo que temos para agir antes de descumprir o contrato com as ONGs."

## Bloco 7 — MTTR: incidente do início ao fim (2,5 min) ⭐

Volte ao terminal do ensaio disparado no bloco 6.

**Na tela**: o terminal do `mttr-drill.sh` + <http://localhost:9090/alerts>.

**Narrar a linha do tempo conforme ela aparece**:

| Momento | O que apontar |
|---|---|
| `T0_INICIO_IMPACTO` | o `ngo-service` foi a zero réplicas |
| `DEGRADACAO_P95` (~+54s) | p95 salta de **21ms para ~1000ms** — mostrar no Grafana |
| — | **nenhuma doação falhou**: `curl -s localhost:8082/donations \| tail -c 300` continua gravando |
| `ALERTA_FIRING` (~+7min) | `DonationServiceHighLatencyP95` fica vermelho em `/alerts` |
| `T3_RECUPERADO` | ArgoCD restaura o serviço — **37s** após ser liberado |
| `T4_FIM_IMPACTO` | alertas resolvidos, p95 volta a ~17ms |

**Os três pontos que a banca precisa ouvir**:

1. **Só o alerta de latência disparou** — nenhum de erro, nenhum de burn rate.
   Isso prova que o *fail-open* funciona: indisponibilidade da dependência
   virou **latência, não erro**, e o **error budget não foi consumido**.
2. **MTTD 424s contra MTTR 37s**: a recuperação é ~11x mais rápida que a
   detecção. Sem segurar o incidente artificialmente, o sistema **se cura antes
   de perceber o problema**.
3. Essa é uma **lacuna real que o ensaio revelou**, registrada como ação
   corretiva em [`postmortem-mttr-demo.md`](postmortem-mttr-demo.md).

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

1. `infra/terraform/envs/primary/providers.tf` — o bloco `default_tags` com
   `Project`, `Environment` e `CostCenter`.
2. Terminal:

```bash
aws resourcegroupstaggingapi get-resources --region us-east-1 \
  --tag-filters Key=Project,Values=SolidaryTech \
  --query 'length(ResourceTagMappingList)'
```

3. **AWS Tag Editor** (rende melhor em vídeo que o terminal):
   <https://us-east-1.console.aws.amazon.com/resource-groups/tag-editor/find-resources>
   → região `us-east-1`, todos os tipos, tag `Project = SolidaryTech`.
4. [`finops-forecast.md`](finops-forecast.md) — a tabela de **~US$ 150/mês** e
   as economias: Spot (−70%), 1 NAT em vez de 2, **DR sob demanda (−100% do
   custo ocioso)**.
5. Rightsizing, com a carga ainda rodando:

```bash
kubectl -n solidarytech top pods
```
   Comparar com os `requests`/`limits` em `gitops/workloads/base/`.

> Se o Cost Explorer ainda não agrupar por tag, **diga isso em voz alta**: a
> ativação como *cost allocation tag* leva até 24h. O Tag Editor prova a
> cobertura de imediato.

> **Frase-chave**: "cada linha dessa conta tem uma decisão de engenharia atrás."

## Bloco 9 — ITSM e AIOps (1,5 min)

**Na tela**:

1. [`itsm-incident-flow.md`](itsm-incident-flow.md) — o diagrama dos 5 estágios.
2. `infra/terraform/newrelic/main.tf` — as condições `type = "baseline"`:
   **anomaly detection como código**, limiar aprendido em vez de fixo.
3. **New Relic** <https://one.newrelic.com/alerts> → as 2 policies
   (`SolidaryTech - donation-service (Hot Path)` e
   `SolidaryTech - plataforma (Kubernetes)`) com as 5 condições.
4. **Alertmanager** <http://localhost:9093> → o agrupamento por `service` e a
   rota do `Watchdog` para o receiver nulo.
5. [`postmortem-mttr-demo.md`](postmortem-mttr-demo.md) — a seção **"O que o
   ensaio refutou"** e a tabela de ações corretivas.

> **Frase-chave**: "detecção preditiva é o limiar aprendido, não o limiar fixo:
> a condição baseline dispara quando o comportamento muda, antes de o SLO ser
> violado."

## Bloco 10 — Disaster Recovery (2 min)

Executar o DR ao vivo custa ~25 min de RTO — **apresente o ensaio registrado**,
que é evidência igualmente válida e cabe no tempo.

**Na tela**:

1. [`dr-plan.md`](dr-plan.md) — Warm Standby (Opção B), **RPO ≤ 1h**,
   **RTO alvo 1h**, e a tabela por tipo de dado.
2. `scripts/activate-dr.sh` — mostrar que é **um comando** e apontar as 4
   etapas descritas no cabeçalho.
3. A seção **"Resultado do ensaio"** do `dr-plan.md`: **RTO medido 24min23s** e
   a prova de RPO — as doações do `us-east-1` retornando íntegras no
   `us-east-2`.

> **Frase-chave**: "as duas doações criadas no `us-east-1` aparecem no
> `us-east-2` com o mesmo `id` e `created_at` — nenhum dado transacional
> perdido."

## Bloco 11 — Encerramento (30 s)

**Na tela**: `terraform destroy` iniciando.

**Falar**: custo por hora × infraestrutura efêmera; link do repositório; e as
pendências **declaradas honestamente** (Workflow do New Relic bloqueado por
entitlement do plano free; ações corretivas 5, 6 e 7 no post-mortem).

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
