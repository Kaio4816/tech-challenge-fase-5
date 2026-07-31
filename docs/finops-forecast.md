# FinOps — Forecast, Tags e Rightsizing

A SolidaryTech é uma ONG: cada dólar gasto em infraestrutura é um dólar que
não vai para a causa. Este documento tem três partes:

1. **Forecast** — quanto custa a arquitetura por mês, item por item.
2. **Recomendações** — o que já foi feito para reduzir esse número e o que
   ainda pode ser feito.
3. **Tags e rightsizing** — como o custo é atribuído (tags obrigatórias) e
   como os `requests`/`limits` dos pods foram dimensionados.

---

## 1. Forecast mensal

Premissas: região `us-east-1`, preços on-demand públicos da AWS (julho/2026),
730 horas/mês (24/7), **um** ambiente de pé (`envs/primary`). O ambiente de DR
(`envs/dr`) não entra no forecast mensal por não ficar de pé — ver seção
["Custo do DR"](#custo-do-dr-sob-demanda).

| # | Recurso (Terraform) | Especificação | Preço unitário | Custo/mês |
|---|---|---|---|---|
| 1 | EKS control plane (`modules/eks`) | 1 cluster, v1.31 | US$ 0,10/h | **US$ 73,00** |
| 2 | EC2 node group (`modules/eks`) | **4** × `t3.medium` **Spot** | ~US$ 0,0125/h (vs. 0,0416 on-demand) | **US$ 36,50** |
| 3 | NAT Gateway (`modules/network`) | 1 único (não 1 por AZ) | US$ 0,045/h + US$ 0,045/GB | **US$ 35,00** |
| 4 | RDS Postgres (`modules/rds-postgres`) | `db.t4g.micro`, single-AZ, 20 GiB gp3 | US$ 0,016/h + US$ 0,115/GB-mês | **US$ 13,98** |
| 5 | EBS dos nós | **4** × 20 GiB gp3 (root dos nós) | US$ 0,08/GB-mês | **US$ 6,40** |
| 6 | EBS dos PVCs (observabilidade) | 10 GiB Prometheus + 10 GiB Loki | US$ 0,08/GB-mês | **US$ 1,60** |
| 7 | CloudWatch Logs | logs do control plane EKS (`api`, `audit`, `authenticator`) | US$ 0,50/GB ingerido | **~US$ 2,50** |
| 8 | ECR (`modules/ecr`) | 3 repositórios + replicação para `us-east-2` | US$ 0,10/GB-mês | **~US$ 0,40** |
| 9 | DynamoDB (`modules/dynamodb`) | PAY_PER_REQUEST + réplica Global Table | US$ 1,25/M writes (1,875 replicados) | **< US$ 1,00** |
| 10 | SQS (`modules/sqs`) | fila + DLQ, volume do hackathon | 1M req/mês grátis, depois US$ 0,40/M | **~US$ 0,05** |
| 11 | S3 (state do Terraform) | versionado, poucos MB | US$ 0,023/GB-mês | **< US$ 0,10** |
| 12 | Transferência de dados de saída | tráfego das demos | US$ 0,09/GB (após 100 GB grátis) | **~US$ 1,00** |
| | **TOTAL 24/7** | | | **≈ US$ 171/mês** |

### O que *não* está na tabela (e por quê)

- **ALB / Ingress (~US$ 20/mês)**: nenhum `Service` do tipo `LoadBalancer` é
  criado. Acesso à UI do ArgoCD, ao Grafana e aos serviços é via
  `kubectl port-forward` (ver README). Isso economiza ~US$ 20/mês **e** evita
  o risco de load balancer criado pelo Kubernetes fora do
  Terraform prendendo o `terraform destroy`). Se a plataforma fosse exposta
  publicamente, somar US$ 16,43 (hora do ALB) + ~US$ 4 (LCUs) ao total.
- **ElastiCache**: citado no README original do desafio, mas nenhum dos três
  serviços usa cache — provisionar seria custo sem contrapartida
  (`cache.t4g.micro` custaria mais US$ 11,68/mês).
- **New Relic**: free tier (100 GB/mês de ingestão, 1 usuário full platform).
  A configuração de `lowDataMode: true` no `nri-bundle` e o
  `newrelic-logging` desligado existem justamente para não estourar esse
  limite e virar custo. Ver `gitops/apps/base/nri-bundle-app.yaml`.
- **SonarCloud / GitHub Actions**: gratuitos em repositório público.

### O custo real deste projeto não é US$ 150/mês

A infra é **efêmera por design**: sobe para testar/gravar e é destruída
(`terraform destroy`) em seguida. O custo relevante é o **custo por hora de
ambiente de pé**:

| Ambiente | Custo/hora |
|---|---|
| `envs/primary` completo | ≈ US$ 0,235/h |
| `envs/dr` completo (durante um ensaio) | ≈ US$ 0,190/h |

Um ciclo de demo de 4 horas com as duas regiões de pé custa **menos de
US$ 1,80**. Foi essa decisão — e não uma negociação de desconto — que tornou o
projeto viável em conta pessoal.

### Custo do DR sob demanda

O warm standby da Fase 6 **não fica de pé**. Se ficasse (padrão "warm standby"
clássico, com cluster e RDS espelhados 24/7 em `us-east-2`), o forecast
dobraria para ≈ US$ 290/mês. Como o `envs/dr` é criado sob demanda por
`scripts/activate-dr.sh`, o custo ocioso do DR é **US$ 0,00**, ao preço de um
RTO de ~25 min (medido no ensaio — ver `dr-plan.md`) em vez de ~5 min.

---

## 2. Recomendações de otimização

### Já implementadas

| Recomendação | Onde | Economia |
|---|---|---|
| **Nós EC2 em Spot** em vez de on-demand | `modules/eks` (`node_capacity_type = "SPOT"`) | US$ 85/mês (−70% do custo de EC2) |
| **1 NAT Gateway em vez de 1 por AZ** | `modules/network` (`single_nat_gateway = true`) | US$ 32,85/mês (−50%; o padrão do módulo VPC é um por AZ) |
| **VPC endpoints gateway (S3 e DynamoDB)** | `modules/network` | Endpoints gateway são gratuitos e tiram o tráfego de imagens/DynamoDB do NAT, que cobra US$ 0,045/GB processado |
| **DR sob demanda em vez de standby permanente** | `envs/dr` + `scripts/activate-dr.sh` | US$ 145/mês (−100% do custo ocioso do DR) |
| **RDS single-AZ `db.t4g.micro` (Graviton)** | `modules/rds-postgres` | Multi-AZ dobraria para US$ 23,36; `db.t3.micro` (Intel) custaria ~10% mais |
| **1 instância RDS com 2 databases** em vez de 2 instâncias | `envs/primary` (`postgresql_database` ×2) | US$ 13,98/mês (metade do custo de RDS) |
| **Sem ALB** (port-forward nas demos) | GitOps — nenhum `Service` `LoadBalancer` | ~US$ 20/mês |
| **Retention curta na observabilidade** (Prometheus 2d, Loki 48h) | `gitops/apps/base/` | Mantém os PVCs em 10 GiB em vez de crescerem indefinidamente |

Resumo: somando a coluna "Economia" (US$ 268/mês) ao forecast atual, a mesma
arquitetura sem nenhuma dessas decisões — nós on-demand, 2 NAT Gateways, DR
permanentemente de pé, ALB exposto, RDS multi-AZ e uma instância RDS por
serviço — custaria **≈ US$ 420/mês**. O forecast atual é **~64% menor**.

### Próximos passos (não implementados)

1. **Trocar o NAT Gateway por uma NAT instance `t4g.nano`** — hoje o NAT é o
   segundo maior item da conta (US$ 35/mês) e serve a um cluster de 4 nós que
   basicamente só busca imagens do ECR. Uma NAT instance custaria ~US$ 3,00/mês
   (−91%), ao preço de perder a alta disponibilidade gerenciada e de ter mais
   um host para operar. Não implementado porque, num projeto cujo cluster fica
   de pé 4 horas por ciclo, o ganho absoluto (~US$ 0,04/hora) não paga a
   complexidade — mas em um cenário 24/7 real seria a primeira otimização a
   fazer.
2. **Compute Savings Plan de 1 ano** para a parte on-demand — se a plataforma
   fosse 24/7 de verdade, um Savings Plan cobriria o control plane... não (EKS
   não é elegível), mas cobriria os nós caso fosse necessário sair do Spot
   (−30 a −40%). Só faz sentido com uso previsível e contínuo, o oposto do
   perfil atual.
3. **AWS Budgets + alerta de custo por tag `CostCenter=NGO-Core`** — hoje o
   controle é comportamental ("destrua depois da demo"). Um budget de
   US$ 20/mês com alerta em 80% transformaria um `terraform destroy` esquecido
   em um e-mail em vez de uma surpresa na fatura. É a recomendação de melhor
   relação esforço/benefício das três.
4. **Reduzir os logs do control plane EKS** — `api`/`audit`/`authenticator`
   são o padrão do módulo e respondem por ~US$ 2,50/mês em CloudWatch. Manter
   só `audit` (ou nenhum, em ambiente de laboratório) elimina quase todo esse
   item.

---

## 3. Estratégia de tags

### Implementação (obrigatoriamente via Terraform)

As três tags exigidas pelo edital são aplicadas via `default_tags` do provider
AWS, **não** tag por tag em cada recurso — assim é impossível esquecer de
taguear um recurso novo:

```hcl
# infra/terraform/envs/primary/providers.tf (idêntico em envs/dr e bootstrap)
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "SolidaryTech"
      Environment = "Production"
      CostCenter  = "NGO-Core"
    }
  }
}
```

O mesmo mapa (`var.tags`) também é passado explicitamente para os módulos que
propagam tags para recursos filhos — em particular o node group do EKS
(`modules/eks`), para alcançar as instâncias EC2 e os volumes EBS criados pelo
Auto Scaling Group, que não são criados diretamente pelo Terraform.

### Evidência das tags

```bash
# 1) Quantos recursos respondem pela tag Project=SolidaryTech (as 3 tags são
#    aplicadas juntas, então uma serve de prova para as três):
aws resourcegroupstaggingapi get-resources \
  --region us-east-1 \
  --tag-filters Key=Project,Values=SolidaryTech \
  --query 'length(ResourceTagMappingList)'

# 2) Listar ARN + tags de cada recurso (evidência detalhada para o relatório):
aws resourcegroupstaggingapi get-resources \
  --region us-east-1 \
  --tag-filters Key=CostCenter,Values=NGO-Core \
  --query 'ResourceTagMappingList[].{ARN:ResourceARN,Tags:Tags[?Key==`Project`||Key==`Environment`||Key==`CostCenter`]}' \
  --output json

# 3) Custo agrupado pela tag CostCenter (Cost Explorer):
aws ce get-cost-and-usage \
  --time-period Start=2026-07-01,End=2026-08-01 \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=TAG,Key=CostCenter
```

Na UI, o mesmo se vê em **Resource Groups → Tag Editor** (filtrando por
`Project=SolidaryTech`) e em **Billing → Cost Explorer** agrupando por tag.

> **Dois detalhes que atrapalham a evidência se não forem conhecidos:**
> 1. Cost Explorer só agrupa por uma tag depois que ela é **ativada como tag
>    de alocação de custos** em Billing → Cost allocation tags, e a ativação
>    leva até 24h para refletir. Ou seja: a evidência de Cost Explorer por tag
>    precisa ser preparada com um dia de antecedência — a evidência via
>    Resource Groups Tagging API (comandos 1 e 2) é imediata e vale como prova
>    de que a estratégia de tags está implementada.
> 2. Alguns tipos de recurso não são tagáveis na AWS (associações de route
>    table, a configuração de replicação do ECR, o OIDC provider do EKS).
>    Eles aparecerão sem tags em qualquer auditoria — é limitação da AWS, não
>    da implementação. A conferência deve ser feita sobre os recursos
>    *tagáveis* (o comando 1 é o número a citar).

---

## 4. Rightsizing dos pods

### Valores configurados

Definidos em `gitops/workloads/base/<serviço>/deployment.yaml`, iguais nos
overlays `primary` e `dr`:

| Serviço | `requests.cpu` | `requests.memory` | `limits.cpu` | `limits.memory` | Réplicas |
|---|---|---|---|---|---|
| `donation-service` (Go) | 50m | 64Mi | 200m | 128Mi | 2–4 (HPA, alvo 70% CPU) |
| `ngo-service` (Python/Flask) | 100m | 128Mi | 300m | 256Mi | 1 |
| `volunteer-service` (Python/Flask) | 100m | 128Mi | 300m | 256Mi | 1 |

Racional das diferenças:

- **Go pede menos que Python**: o binário do `donation-service` roda em
  `distroless/static` sem runtime nem intérprete; os serviços Flask carregam
  interpretador + Gunicorn + `opentelemetry-instrument`, o que por si só
  ocupa ~100 MiB antes de atender a primeira requisição.
- **`requests` baixo, `limits` ~4× maior**: `requests` é o que o scheduler
  reserva (e a base de cálculo do HPA); `limits` é o teto de burst. Em um
  cluster de 4 × `t3.medium` (2 vCPU / 4 GiB cada), um `requests` folgado
  esgotaria a capacidade alocável antes de a CPU ser realmente usada.
- **Só o Hot Path tem HPA**: `donation-service` escala de 2 a 4 réplicas a 70%
  de CPU sobre o `request` (ou seja, ~35m de uso médio). `ngo-service` e
  `volunteer-service` ficam em 1 réplica — escalá-los seria pagar por
  capacidade que os SLOs não exigem.
- **`limits.memory` = 2× `requests.memory`** em todos: memória é
  incompressível (estourar o limit = OOMKill), então a margem é deliberada.

### Como esses números são validados

O rightsizing só é honesto com dado de uso real sob carga. O procedimento é:

```bash
# 1) Carga real no Hot Path (o metrics-server já está instalado como addon):
kubectl -n solidarytech port-forward svc/donation-service 8082:8082 &
kubectl -n solidarytech port-forward svc/ngo-service 8081:8081 &
./scripts/load-test.sh 10m 20

# 2) Consumo observado durante a carga:
kubectl -n solidarytech top pods

# 3) Comparar com o configurado:
kubectl -n solidarytech get deploy -o custom-columns=\
'NAME:.metadata.name,CPU_REQ:.spec.template.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.template.spec.containers[0].resources.requests.memory'

# 4) Conferir se o HPA reagiu (prova de que o request está calibrado):
kubectl -n solidarytech get hpa donation-service -w
```

Regra de ajuste: `requests` ≈ p95 do uso observado; `limits` ≈ 2–4× o
`requests` para CPU e 2× para memória. Se o `top pods` mostrar uso muito
abaixo do `request`, sobra capacidade paga e ociosa; se o HPA nunca sair de 2
réplicas sob carga, o `request` de CPU está alto demais para o alvo de 70%.

> **Status desta validação**: os valores da tabela são as estimativas de
> partida da Fase 4, e o procedimento acima já foi exercitado contra o
> `docker compose` local (18k requisições via `hey`, Fase 5). A medição com
> `kubectl top` **no cluster real sob carga** faz parte da demo de MTTR ainda
> pendente da Fase 5 — é lá que os números finais devem ser confirmados ou
> ajustados. Está registrado aqui, e não omitido, porque um forecast que
> apresenta estimativa como medição não serve para decidir nada.

### Saturação do cluster (o outro lado do rightsizing)

> ⚠️ **Por que 4 nós e não 2** (medido no cluster real, 2026-07-25): o limite que
> forçou a subida **não foi CPU nem memória — foi pods por nó**. O VPC CNI da AWS
> aloca IPs por interface de rede, e um `t3.medium` comporta 3 ENIs × 6 IPs − 1 =
> **17 pods**. Com a stack de observabilidade, os 2 nós bateram esse teto com CPU
> em ~50% e memória em ~45%: qualquer painel de recurso mostraria o cluster
> folgado, enquanto pods ficavam `Pending` com `Too many pods`.
>
> Isso **dobrou os itens 2 e 5** da tabela (US$ 21,45/mês a mais). Existe uma
> alternativa de custo zero, registrada no código e não aplicada por exigir
> reciclar os nós: `ENABLE_PREFIX_DELEGATION` no addon `vpc-cni`, que eleva o teto
> para ~110 pods/nó e permitiria voltar a 2 nós. É a primeira otimização da fila.

Rightsizing não é só o pod: é o pod *dentro* do nó. Com 4 × `t3.medium`
(~3,5 GiB alocáveis por nó), a soma dos `requests` da plataforma
(kube-prometheus-stack + Loki + Promtail + ArgoCD + `nri-bundle`) é bem maior
que a dos três serviços — é o principal risco de saturação. Foi por isso que a
Fase 5 desligou `newrelic-logging` e `nri-prometheus` no `nri-bundle` (logs já
vão via Loki) e fixou `retention: 2d` no Prometheus. Se a memória apertar, a
ordem de corte é: `nri-bundle` → Loki → subir para `t3.large` (que somaria
US$ 18,25/mês em Spot, dobrando o item nº 2 do forecast).

---

## Referências

- SLOs e error budget: [`sre-slo.md`](sre-slo.md)
- Fluxo de incidentes e alertas: [`itsm-incident-flow.md`](itsm-incident-flow.md)
- Custo do DR e RTO/RPO: [`dr-plan.md`](dr-plan.md)
- Arquitetura e inventário de recursos: [`architecture.md`](architecture.md)
