# SolidaryTech — Ecossistema de microsserviços (Hackathon POSTECH DCLT, Fase 5)

Plataforma que conecta ONGs, doadores e voluntários, entregue como ecossistema
completo: 3 microsserviços conteinerizados, infraestrutura 100% em Terraform,
CI/CD com DevSecOps, entrega contínua por GitOps, observabilidade com SLOs,
FinOps, AIOps/ITSM e Disaster Recovery cross-region.

| | |
|---|---|
| **Cloud** | AWS — EKS 1.31 (`us-east-1`), DR em `us-east-2` |
| **IaC** | Terraform (state em S3 com lock nativo) |
| **CI/CD** | GitHub Actions — testes, Semgrep, SonarCloud, SCA, Trivy, push ECR via OIDC |
| **GitOps** | ArgoCD (app-of-apps) + Kustomize |
| **Observabilidade** | Prometheus, Grafana, Loki, OpenTelemetry, New Relic |
| **SLO do Hot Path** | 99,9%/30d de disponibilidade; p95 < 300ms |
| **DR** | Warm standby por Terraform modularizado — **RTO medido: 24min23s**, RPO ≤ 1h |
| **Custo** | ≈ US$ 150/mês se 24/7; **≈ US$ 0,20/hora** na prática (infra efêmera) |

> ⚠️ **A infraestrutura desta plataforma é efêmera por design.** Ela sobe para
> testes/demonstração e é destruída depois (`terraform destroy`). Enquanto
> estiver de pé, gera custo real na conta AWS — ver
> [`docs/finops-forecast.md`](docs/finops-forecast.md).

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | diagramas, componentes, decisões de arquitetura e seus motivos |
| [`docs/sre-slo.md`](docs/sre-slo.md) | SLIs, SLOs, SLA, error budget, burn rate, dashboard, roteiro de MTTR |
| [`docs/finops-forecast.md`](docs/finops-forecast.md) | forecast mensal, recomendações de otimização, tags, rightsizing |
| [`docs/itsm-incident-flow.md`](docs/itsm-incident-flow.md) | Detecção → Alerta → Tratamento → Post-Mortem → Comunicação; AIOps |
| [`docs/dr-plan.md`](docs/dr-plan.md) | plano de continuidade: RTO/RPO, runbook de ativação, resultado do ensaio |
| [`docs/postmortem-template.md`](docs/postmortem-template.md) | template de post-mortem blameless |
| [`docs/postmortem-mttr-demo.md`](docs/postmortem-mttr-demo.md) | post-mortem do incidente da demo de MTTR |
| [`docs/video-script.md`](docs/video-script.md) | roteiro da gravação da demonstração |

## Estrutura do repositório

```text
.
├── apps/                       # 3 microsserviços (código, Dockerfile, testes, db/init.sql)
│   ├── ngo-service/            #   Python/Flask  :8081  → Postgres
│   ├── donation-service/       #   Go            :8082  → Postgres + SQS   (Hot Path)
│   └── volunteer-service/      #   Python/Flask  :8083  → DynamoDB
├── infra/terraform/
│   ├── bootstrap/              # bucket S3 do state (roda 1×)
│   ├── modules/                # network, eks, rds-postgres, sqs, dynamodb, ecr, irsa
│   ├── envs/{primary,dr}/      # us-east-1 / us-east-2 — mesmos módulos, states isolados
│   └── newrelic/               # alert policies, anomalias (baseline), Workflow → e-mail
├── gitops/
│   ├── bootstrap/install.sh    # Helm install do ArgoCD + Application raiz
│   ├── apps/                   # Applications ArgoCD (serviços + plataforma)
│   ├── platform/               # ServiceMonitors, PrometheusRules (SLO), dashboard Grafana
│   └── workloads/              # Kustomize: base + overlays primary/dr
├── .github/workflows/          # ci-<serviço>.yml ×3
├── scripts/                    # deploy-primary.sh, activate-dr.sh, load-test.sh
└── docs/
```

---

## Rodar localmente (custo zero, sem conta AWS)

```bash
docker compose up --build
```

Sobe Postgres (2 databases), DynamoDB Local (tabela criada automaticamente) e os
3 serviços.

```bash
# Smoke test
curl localhost:8081/health && curl localhost:8082/ready && curl localhost:8083/metrics

# Fluxo ponta a ponta
NGO=$(curl -s -X POST localhost:8081/ngos -H 'Content-Type: application/json' \
  -d '{"name":"ONG Teste","email":"teste@ong.org","cause":"Educação","city":"São Paulo"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
curl -s -X POST localhost:8082/donations -H 'Content-Type: application/json' \
  -d "{\"ngo_id\": $NGO, \"amount\": 50.0, \"donor_name\": \"Doador\"}"
curl -s localhost:8082/donations
```

Testes unitários (não precisam do compose):

```bash
# Go
cd apps/donation-service && docker run --rm -v "$(pwd)":/src -w /src golang:1.25-alpine go test ./... -v

# Python (ngo-service ou volunteer-service)
cd apps/<serviço> && docker run --rm -v "$(pwd)":/app -w /app python:3.12-slim \
  sh -c "pip install -q -r requirements-dev.txt && pytest -v"
```

---

## Runbook — subir o ambiente completo na AWS

Pré-requisitos: AWS CLI autenticado, `terraform` ≥ 1.9, `kubectl`, `helm`,
`docker`, e (para o teste de carga) `hey`.

### Passo 0 — Bootstrap do state (uma única vez por conta)

```bash
cd infra/terraform/bootstrap
terraform init && terraform apply
terraform output -raw bucket_name    # anote: solidarytech-tfstate-<account_id>
```

Este bucket **não** é destruído nos ciclos seguintes (`prevent_destroy`).

### Passo 1 — Infraestrutura (`envs/primary`, ~90 recursos, ~15–20 min)

```bash
cd ../envs/primary
cp backend.hcl.example backend.hcl        # preencher com o bucket do passo 0
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan && terraform apply tfplan
```

### Passo 2 — Schema, Secrets e ArgoCD (um comando)

```bash
cd ../../../..    # raiz do repositório
REPO_URL=https://github.com/Kaio4816/tech-challenge-fase-5.git ./scripts/deploy-primary.sh

# Opcional (habilita traces OTLP + nri-bundle no New Relic):
NEW_RELIC_LICENSE_KEY=<license-key> \
  REPO_URL=https://github.com/Kaio4816/tech-challenge-fase-5.git ./scripts/deploy-primary.sh
```

O script configura o `kubectl`, aplica `apps/*/db/init.sql` nos dois databases,
cria os Secrets a partir dos `terraform output` e instala o ArgoCD apontado para
o overlay `primary`.

### Passo 3 — Acompanhar o sync

```bash
kubectl -n argocd get applications      # solidarytech-root + 8 Applications → Healthy/Synced
kubectl -n solidarytech get pods,hpa
kubectl -n monitoring get pods
```

`nri-bundle` fica `OutOfSync` de propósito enquanto não houver license key do
New Relic (ver [`docs/itsm-incident-flow.md`](docs/itsm-incident-flow.md)).

### Passo 4 — Acessar as UIs (sem expor LoadBalancer)

```bash
# ArgoCD  → https://localhost:8080
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Grafana → http://localhost:3000 (admin / prom-operator)
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

# Prometheus → http://localhost:9090/alerts
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

# Serviços
kubectl -n solidarytech port-forward svc/donation-service 8082:8082
kubectl -n solidarytech port-forward svc/ngo-service 8081:8081
```

### Passo 5 — Validar o fluxo de negócio no cluster

```bash
# com os port-forwards de ngo/donation ativos
curl -X POST localhost:8081/ngos -H 'Content-Type: application/json' \
  -d '{"name":"ONG Real","email":"real@ong.org","cause":"Saúde","city":"Recife"}'
curl -X POST localhost:8082/donations -H 'Content-Type: application/json' \
  -d '{"ngo_id": 1, "amount": 123.45, "donor_name": "Doador Real"}'
curl -s localhost:8082/donations                     # gravou no RDS
aws sqs receive-message --queue-url "$(terraform -chdir=infra/terraform/envs/primary output -raw sqs_queue_url)"
```

### Passo 6 — Carga, SLO e demo de MTTR

```bash
./scripts/load-test.sh 10m 20    # gera carga real no Hot Path (via hey)
```

Com o dashboard "SolidaryTech - SRE Golden Metrics & SLO" aberto no Grafana,
seguir o roteiro cronometrado de
[`docs/postmortem-mttr-demo.md`](docs/postmortem-mttr-demo.md#reprodução-roteiro-do-ensaio).

### Passo 7 (opcional) — Alertas e AIOps no New Relic

```bash
export NEW_RELIC_ACCOUNT_ID=... NEW_RELIC_API_KEY=NRAK-... NEW_RELIC_REGION=US
cd infra/terraform/newrelic
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform apply -var 'alert_emails=["seu-email@exemplo.com"]'
```

---

## Runbook — Disaster Recovery

```bash
# Ativar a região de contingência (um comando; ~25 min)
REPO_URL=https://github.com/Kaio4816/tech-challenge-fase-5.git ./scripts/activate-dr.sh
```

Snapshot on-demand do RDS → cópia cross-region → `terraform apply` no `envs/dr`
→ Secrets → ArgoCD com overlay `dr`. Procedimento completo, RTO/RPO e resultado
do ensaio em [`docs/dr-plan.md`](docs/dr-plan.md).

---

## Runbook — destruir tudo (fazer sempre ao terminar)

```bash
# 1) DR, se tiver sido ativado
cd infra/terraform/envs/dr && terraform destroy

# 2) Primary
cd ../primary
terraform apply -target=module.rds   # só se seu IP público mudou desde o apply (ver abaixo)
terraform destroy

# 3) Snapshots manuais criados pelo activate-dr.sh (o Terraform não os remove)
aws rds describe-db-snapshots --snapshot-type manual --region us-east-1 \
  --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
aws rds delete-db-snapshot --db-snapshot-identifier <id> --region us-east-1
aws rds delete-db-snapshot --db-snapshot-identifier <id> --region us-east-2

# 4) Conferir que não sobrou nada com tag do projeto
aws resourcegroupstaggingapi get-resources --region us-east-1 \
  --tag-filters Key=Project,Values=SolidaryTech --query 'length(ResourceTagMappingList)'
aws resourcegroupstaggingapi get-resources --region us-east-2 \
  --tag-filters Key=Project,Values=SolidaryTech --query 'length(ResourceTagMappingList)'
```

O bucket de state (passo 0) e a configuração do New Relic sobrevivem de
propósito — custo desprezível e reconstruir a cada ciclo não agrega nada.

### Problemas conhecidos no `destroy` (todos já vistos de verdade)

| Sintoma | Causa | Solução |
|---|---|---|
| Trava ~11 min em subnets/SGs | ENI órfã do VPC CNI (`available`, não anexada) que o EKS não limpou | `aws ec2 describe-network-interfaces --filters Name=subnet-id,Values=<id>` → `aws ec2 delete-network-interface --network-interface-id <eni>` |
| Timeout em `DROP DATABASE` | o SG do RDS libera 5432 só para o IP de quem aplicou; seu IP mudou | `terraform apply -target=module.rds` antes do `destroy` (recalcula `data.http.my_ip`) |
| `Error acquiring the state lock` | queda de rede durante um apply/destroy anterior deixou o lock no S3 | `terraform force-unlock -force <lock-id>` (só se nenhum outro processo estiver rodando) |
| `RepositoryNotEmptyException` no ECR | imagens empurradas pela CI | já resolvido: `force_delete = true` no módulo `ecr` |

---

## CI/CD

Um workflow por serviço (`.github/workflows/ci-<serviço>.yml`), disparado por
push/PR com path filter:

```
test → sast (Semgrep) ─┬→ sonar (SonarCloud) ─┬→ build → scan-image (Trivy)
                       └→ sca (govulncheck /  ┘        → push (ECR via OIDC)
                          pip-audit + trivy fs)        → gitops (bump da imagem)
```

O job `gitops` faz `kustomize edit set image` no overlay `primary` e commita com
`[skip ci]`; o ArgoCD detecta o commit e sincroniza — CD ponta a ponta, sem
`kubectl` manual.

Variáveis/segredos esperados no repositório (Settings → Secrets and variables →
Actions):

| Nome | Habilita | Status |
|---|---|---|
| `vars.AWS_ECR_ROLE_ARN` | jobs `push` e `gitops` (criado pelo módulo `irsa`) | configurado |
| `vars.SONAR_ORGANIZATION` + `secrets.SONAR_TOKEN` | job `sonar` | pendente (job fica `skipped`, pipeline segue verde) |

`workflow_dispatch` **não** executa `push`/`gitops` (guardados por
`github.event_name == 'push'`): para reconstruir imagens depois de recriar o ECR,
é preciso um push real em um arquivo dentro do path filtrado.

---

## Mapa de requisitos → evidências

| Requisito do edital | Onde está |
|---|---|
| Dockerfiles otimizados | `apps/*/Dockerfile` (multi-stage; Go em `distroless`, Python não-root) |
| Deploy em Kubernetes gerenciado | EKS via `infra/terraform/modules/eks` |
| Terraform: cluster, banco, mensageria, rede | `infra/terraform/{modules,envs}` |
| CI/CD com Build, Testes, SAST, SCA, Trivy, SonarQube-equivalente | `.github/workflows/ci-*.yml` |
| GitOps (ArgoCD/FluxCD) | `gitops/` (ArgoCD app-of-apps) |
| Prometheus + Grafana + Loki/OTel | `gitops/apps/base/`, `gitops/platform/` |
| New Relic + Distributed Tracing | OTLP nos 3 serviços + `nri-bundle` + `infra/terraform/newrelic/` |
| SLI/SLO/SLA + Dashboard + Error Budget | [`docs/sre-slo.md`](docs/sre-slo.md), `gitops/platform/` |
| MTTR | [`docs/postmortem-mttr-demo.md`](docs/postmortem-mttr-demo.md) |
| Tags FinOps via Terraform | `default_tags` nos providers; evidência em [`docs/finops-forecast.md`](docs/finops-forecast.md) |
| Rightsizing (requests/limits) | `gitops/workloads/base/*/deployment.yaml` + [`docs/finops-forecast.md`](docs/finops-forecast.md) |
| Forecast + recomendação de otimização | [`docs/finops-forecast.md`](docs/finops-forecast.md) |
| AIOps (IA da ferramenta habilitada) | condições `baseline` em `infra/terraform/newrelic/main.tf` |
| Ciclo de vida de incidentes (ITSM) | [`docs/itsm-incident-flow.md`](docs/itsm-incident-flow.md) |
| Plano de Continuidade + RTO/RPO | [`docs/dr-plan.md`](docs/dr-plan.md) |
| DR — Opção B (warm standby, um comando) | `scripts/activate-dr.sh` + `infra/terraform/envs/dr` |

## Estado do projeto

Implementado e **verificado contra a AWS real**: aplicações + Docker, CI/CD
(pipeline verde ponta a ponta com push real no ECR), Terraform do `envs/primary`
(apply e destroy limpos), GitOps (3 Applications `Healthy`/`Synced`, CD
automático) e Disaster Recovery (ensaio completo, RTO 24min23s, RPO comprovado).

Pendência conhecida: o roteamento automático de alerta por e-mail no New Relic
(`newrelic_workflow`) é bloqueado no plano gratuito. Policies, condições e
tracing distribuído funcionam normalmente — ver
[`docs/postmortem-mttr-demo.md`](docs/postmortem-mttr-demo.md).
