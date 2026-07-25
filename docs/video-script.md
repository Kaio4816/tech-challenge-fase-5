# Roteiro do vídeo de demonstração

Objetivo: demonstrar **funcionando** cada requisito do edital — a regra de
avaliação é explícita ("não basta configurar"). O roteiro abaixo é otimizado
para isso: mostra artefato + execução + resultado, na ordem que minimiza tempo
de espera na gravação.

**Duração alvo: 12–15 min.**

---

## Antes de gravar (checklist de preparação)

Estes passos levam 30–40 min e **não** devem ser gravados em tempo real:

- [ ] `terraform apply` do `envs/primary` concluído (~90 recursos).
- [ ] `./scripts/deploy-primary.sh` executado **com** `NEW_RELIC_LICENSE_KEY`.
- [ ] `solidarytech-root` + 8 Applications `Healthy`/`Synced`.
- [ ] `infra/terraform/newrelic` aplicado (policies, anomalias e Workflow criados).
- [ ] Dados de seed: 1 ONG + 2 doações (para provar o RPO depois).
- [ ] Tags de alocação de custo **ativadas** em Billing (ver
      [`finops-forecast.md`](finops-forecast.md) — leva até 24h para o Cost
      Explorer agrupar por tag).
- [ ] `hey` instalado; port-forwards prontos em terminais separados:
      ArgoCD (8080), Grafana (3000), Prometheus (9090), donation (8082), ngo (8081).
- [ ] Abas do navegador abertas e logadas: GitHub Actions, SonarCloud, ArgoCD,
      Grafana, Prometheus/Alerts, New Relic, AWS Tag Editor, AWS Cost Explorer.
- [ ] Se for gravar o DR ao vivo: começar o `activate-dr.sh` **antes** do bloco
      6 e voltar a ele depois (~25 min de RTO); alternativa é apresentar o
      resultado do ensaio já registrado em [`dr-plan.md`](dr-plan.md).

---

## Bloco 1 — Abertura e arquitetura (1 min)

**Falar**: nome, RM, o que é a SolidaryTech e os 4 objetivos da diretoria
(doações não param, custo controlado, resposta preditiva, SLO/SLA claros).

**Mostrar**: diagrama de [`architecture.md`](architecture.md) e a estrutura do
monorepo (`apps/`, `infra/`, `gitops/`, `docs/`).

**Frase-chave**: "o `donation-service` é o Hot Path — tudo que vem a seguir gira
em torno de manter esse caminho de pé."

## Bloco 2 — Fundação DevOps: Docker, Terraform, EKS (2 min)

**Mostrar**:
1. `apps/donation-service/Dockerfile` — multi-stage, `distroless/static:nonroot`.
2. `infra/terraform/modules/` — os 7 módulos; abrir `modules/eks` (Spot) e
   `modules/rds-postgres`.
3. No terminal:
   ```bash
   kubectl get nodes -o wide            # nós Ready, capacityType SPOT
   kubectl -n solidarytech get pods
   ```

**Frase-chave**: "nada aqui foi criado pelo console — o cluster, o banco, a
fila e a tabela saem todos de `terraform apply`."

## Bloco 3 — CI/CD DevSecOps (2 min)

**Mostrar**:
1. GitHub Actions: um run **verde completo** com os jobs
   `test → sast → sca → build → scan-image → push → gitops`.
2. Abrir o job `scan-image` (Trivy) e o `sast` (Semgrep) — mostrar que
   HIGH/CRITICAL falha o pipeline.
3. SonarCloud com o projeto populado.
4. O commit automático `chore(gitops): bump ... [skip ci]` no histórico.

**Frase-chave**: "o pipeline não faz deploy — ele altera o Git. Quem faz deploy
é o ArgoCD."

## Bloco 4 — GitOps ponta a ponta (2 min)

**Mostrar**:
1. UI do ArgoCD: `solidarytech-root` como app-of-apps, 8 Applications
   `Healthy`/`Synced`.
2. **CD ao vivo** (o momento mais convincente do vídeo):
   ```bash
   # após um push que dispare a CI, ou reusando o commit de bump do bloco 3:
   kubectl -n argocd get application donation-service -w
   kubectl -n solidarytech get pods -w
   ```
3. **Self-heal ao vivo** (5 s, sempre funciona):
   ```bash
   kubectl -n solidarytech scale deploy/volunteer-service --replicas=3
   kubectl -n solidarytech get pods -w      # ArgoCD reverte para 1
   ```

**Frase-chave**: "o estado desejado está no Git; qualquer divergência é
revertida sozinha."

## Bloco 5 — Fluxo de negócio real (1 min)

```bash
curl -X POST localhost:8081/ngos -H 'Content-Type: application/json' \
  -d '{"name":"ONG Demo","email":"demo@ong.org","cause":"Educação","city":"São Paulo"}'
curl -X POST localhost:8082/donations -H 'Content-Type: application/json' \
  -d '{"ngo_id": 1, "amount": 250.00, "donor_name": "Doador Demo"}'
curl -s localhost:8082/donations
```

**Mostrar também**: mensagem chegando no SQS (`aws sqs receive-message`) e o
item no DynamoDB após um `POST /volunteers` — prova de IRSA funcionando (sem
access key em nenhum pod).

## Bloco 6 — Observabilidade e SRE (3 min)

**Mostrar**:
1. `docs/sre-slo.md`: os 2 SLIs, SLO 99,9%, **SLA 99,5%**, error budget de
   43,2 min/30d.
2. Grafana, dashboard "SolidaryTech - SRE Golden Metrics & SLO" **sob carga**:
   ```bash
   ./scripts/load-test.sh 5m 20
   ```
   Apontar: traffic, taxa de erro, p50/p95/p99, saturação, e os gauges de
   **error budget** e **burn rate**.
3. New Relic: **distributed tracing** com o trace `donation-service → ngo-service`
   (abrir o span da chamada `GET /ngos/{id}` dentro do trace do `POST /donations`)
   e a tela de anomalias/issues do Applied Intelligence.
4. Prometheus → `/alerts`: as 5 regras carregadas.

**Frase-chave**: "o SLO é mais rígido que o SLA de propósito — a folga é o tempo
que temos para agir antes de descumprir o contrato com as ONGs."

## Bloco 7 — MTTR ao vivo (2 min) ⭐

O bloco mais importante do requisito de SRE. Roteiro completo em
[`postmortem-mttr-demo.md`](postmortem-mttr-demo.md#reprodução-roteiro-do-ensaio).

```bash
# 1) carga já rodando do bloco 6; anotar o horário exato:
date -u +%H:%M:%S && kubectl -n solidarytech scale deploy/ngo-service --replicas=0
```

**Narrar enquanto acontece**:
- p95 sobe no dashboard (~2s) — **mas nenhuma doação falha**: a validação é
  fail-open, então a falha aparece como latência, não como erro.
- `SolidaryTechTargetDown` e `DonationServiceHighLatencyP95` → `Firing`.
- E-mail do Workflow do New Relic chegando (mostrar a caixa de entrada).
- ArgoCD detecta o drift e faz `selfHeal` — **ninguém digita nada**.
- p95 volta abaixo de 300ms; anotar o horário → **MTTR medido**.

**Frase-chave**: "MTTR de X minutos, sem intervenção humana — foi a
observabilidade que detectou e a automação que corrigiu."

## Bloco 8 — FinOps (1,5 min)

**Mostrar**:
1. `default_tags` no `providers.tf` e a evidência:
   ```bash
   aws resourcegroupstaggingapi get-resources --region us-east-1 \
     --tag-filters Key=Project,Values=SolidaryTech --query 'length(ResourceTagMappingList)'
   ```
   + AWS Tag Editor filtrando `Project=SolidaryTech` (visual, fica melhor no vídeo).
2. Cost Explorer agrupado por tag `CostCenter`.
3. [`finops-forecast.md`](finops-forecast.md): a tabela de ~US$ 150/mês e as
   economias (Spot −70%, 1 NAT, **DR sob demanda −100% do custo ocioso**).
4. Rightsizing: `kubectl -n solidarytech top pods` **durante a carga**,
   comparado com os `requests`/`limits` dos manifests.

**Frase-chave**: "cada linha dessa conta tem uma decisão de engenharia atrás —
a mesma arquitetura sem elas custaria US$ 420/mês."

## Bloco 9 — ITSM e AIOps (1,5 min)

**Mostrar**:
1. [`itsm-incident-flow.md`](itsm-incident-flow.md): o diagrama dos 5 estágios.
2. `infra/terraform/newrelic/main.tf`: as condições `baseline`
   (**anomaly detection como código**) e o Workflow com enrichment NRQL.
3. New Relic: a policy, as condições e o Workflow criados; o issue gerado pelo
   incidente do bloco 7.
4. [`postmortem-mttr-demo.md`](postmortem-mttr-demo.md) com o MTTR do bloco 7 já
   preenchido, e os modelos de comunicação a diretoria/ONGs.

**Frase-chave**: "detecção preditiva é o limiar aprendido, não o limiar fixo: a
condição baseline dispara quando o comportamento muda, antes de o SLO ser
violado."

## Bloco 10 — Disaster Recovery (2 min)

**Mostrar**:
1. [`dr-plan.md`](dr-plan.md): estratégia Opção B, RPO ≤ 1h, RTO alvo 1h e a
   tabela por tipo de dado.
2. `scripts/activate-dr.sh` — o "um comando".
3. **A prova de RPO** (com o DR já de pé):
   ```bash
   kubectl config use-context <cluster de us-east-2>
   kubectl -n solidarytech port-forward svc/donation-service 8082:8082
   curl -s localhost:8082/donations      # as doações do primary estão aqui
   ```
4. **RTO medido: 24min23s** (ensaio registrado em `dr-plan.md`).

**Frase-chave**: "as duas doações criadas no `us-east-1` aparecem no
`us-east-2` com o mesmo `id` e `created_at` — nenhum dado transacional perdido."

## Bloco 11 — Encerramento (30 s)

**Mostrar**: `terraform destroy` iniciando e a verificação de recursos órfãos.

**Falar**: custo por hora × infra efêmera; link do repositório; pendências
declaradas honestamente (o que ficou como backlog no post-mortem).

**Frase-chave**: "a infraestrutura inteira sobe e desce por comando — é isso que
torna o DR sob demanda viável e a conta pagável por uma ONG."

---

## Dicas de gravação

- **Terminal grande** (fonte ≥ 16pt): comando ilegível não é evidência.
- Antes de cada bloco de terminal, `clear` — a rolagem confunde.
- Evite silêncios longos: quando algo demora (sync, apply, alerta), continue
  narrando o **porquê** enquanto espera.
- Ao mostrar um arquivo, aponte **as 2 ou 3 linhas que importam**, não o arquivo
  inteiro.
- O bloco 7 (MTTR) precisa de horário visível em tela — deixar um `date -u` antes
  e depois do impacto é o que sustenta o número no relatório.
- Se algo falhar ao vivo: **não corte**. Explicar o diagnóstico ao vivo é
  exatamente a competência avaliada em SRE.

## Mapa vídeo → requisitos do edital

| Bloco | Requisito coberto |
|---|---|
| 2 | Docker, Kubernetes, Terraform (cluster/banco/mensageria/rede) |
| 3 | CI/CD, DevSecOps (Build, Testes, SAST, SCA, Trivy, SonarQube-equivalente) |
| 4 | GitOps |
| 5 | funcionamento real dos 3 microsserviços |
| 6 | Observabilidade (Prometheus/Grafana/Loki/OTel + New Relic + tracing), SLI/SLO/SLA, dashboard, error budget |
| 7 | MTTR |
| 8 | FinOps (tags, forecast, rightsizing, otimização) |
| 9 | AIOps + ITSM (ciclo completo do incidente) |
| 10 | Plano de Continuidade, RTO/RPO, DR Opção B |
