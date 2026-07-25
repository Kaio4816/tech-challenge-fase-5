# Plano de Disaster Recovery — SolidaryTech

## Objetivo

Se a região primária (`us-east-1`) ficar indisponível, as doações não podem
parar: este documento define a estratégia de continuidade, os alvos de RTO/RPO
para os dados de doações, e o runbook de ativação do ambiente de
contingência.

## Estratégia: Warm Standby via Terraform modularizado (Opção B do edital)

Não há um cluster de DR de pé o tempo todo — isso violaria o princípio de
custo mínimo do projeto (infra efêmera, `terraform destroy` entre demos). Em
vez disso, `infra/terraform/envs/dr` (`us-east-2`) reusa exatamente os
mesmos módulos de `envs/primary` (`network`, `eks`, `rds-postgres`, `sqs`,
`irsa`), parametrizados para outra região, e fica pronto para ser aplicado
**sob demanda** com um único comando: `scripts/activate-dr.sh`. É essa
reutilização de módulo — não um pipeline de replicação contínua rodando 24/7
— que materializa o "ambiente espelho" pedido pela Opção B.

| Dado | Estratégia de DR | RPO |
|---|---|---|
| Postgres (`ngo_db`, `donation_db`) — RDS | Snapshot copiado cross-region no momento da ativação | ≤ 1h (ver justificativa abaixo) |
| Voluntários — DynamoDB | **Global Table** (réplica nativa em `us-east-2`, streams habilitados) | ~0 (replicação contínua da AWS, nada a fazer na ativação) |
| Fila de notificação — SQS | Recriada do zero pelo Terraform no `envs/dr` | N/A — fila é transiente, não transacional (ver "Perdas aceitas" abaixo) |
| Imagens de container — ECR | Replicação cross-region habilitada na conta (`enable_replication` no módulo `ecr` do `envs/primary`) | ~tempo de replicação da AWS (minutos), já resolvido antes do failover |

## RPO — Recovery Point Objective

**Alvo: RPO ≤ 1h para os dados de doações (Postgres).**

Justificativa: `scripts/activate-dr.sh` tira um snapshot novo do RDS do
primary (`aws rds create-db-snapshot`) **no momento em que é executado**,
antes de copiá-lo para `us-east-2` — ou seja, o RPO efetivo é o tempo entre
a última doação gravada e o instante em que o script roda, não uma cópia
periódica desatualizada. Num failover real (ativação em resposta a um
incidente em andamento), isso fica na casa de minutos, bem abaixo do alvo de
1h.

Só cai no cenário de pior caso — reusar o snapshot automático mais recente
(`backup_retention_period = 1` dia, ver `modules/rds-postgres`) — se o
primary já estiver genuinamente inacessível para tirar um snapshot novo (ex.:
falha real da região, não apenas o ensaio simulado). Esse é o único caso em
que o RPO poderia se aproximar de 24h; está documentado aqui como limitação
conhecida (ver "Limitações conhecidas" abaixo), e não é o caminho testado no
ensaio (que "perde" o primary de forma simulada, com a instância RDS ainda
íntegra e acessível para o snapshot on-demand).

DynamoDB (voluntários) não depende dessa lógica: a Global Table já mantém
uma réplica continuamente atualizada em `us-east-2`, então o RPO para esse
dado é efetivamente próximo de zero, sem nenhuma ação no momento da
ativação.

## RTO — Recovery Time Objective

**Alvo: RTO ≤ 1h.**

Composição estimada, validada no ensaio (ver "Resultado do ensaio" abaixo):

| Etapa | Tempo estimado |
|---|---|
| Snapshot + cópia cross-region (`aws rds create-db-snapshot` + `copy-db-snapshot`, aguardando `available` nas duas regiões) | ~5–10 min |
| `terraform apply -auto-approve` no `envs/dr` (rede + **EKS** — a etapa mais demorada, criação de cluster e node group — + RDS restaurado do snapshot + SQS + IRSA) | ~15–20 min |
| Bootstrap do ArgoCD (`gitops/bootstrap/install.sh dr`) + sync inicial das 3 Applications até `Healthy`/`Synced` | ~5 min |
| **Total (ensaio)** | **~35–45 min** |

O gargalo é a criação do cluster EKS do zero (~15 min só para os nós
ficarem `Ready`) — é o custo de não manter o standby permanentemente de pé,
trade-off deliberado em troca de custo de infraestrutura zero fora dos
ensaios/demos.

## Perdas aceitas num failover

- **Fila SQS**: os eventos de notificação de doação enfileirados no primary
  no momento do failover **não são migrados** — a fila do `envs/dr` nasce
  vazia. Aceitável porque a fila é usada para notificação assíncrona
  (best-effort), não para o registro transacional da doação em si (que já
  está persistido no Postgres/RDS antes da mensagem ser publicada — ver
  `donation-service/main.go`). Nenhuma doação é perdida; apenas notificações
  em trânsito no exato instante do failover.
- **Escritas entre o snapshot e o failover real**: qualquer doação gravada
  no primary *depois* do snapshot usado pela ativação (ex.: se o primary
  ficar fora do ar entre o snapshot e a detecção do incidente) não estará
  no DR. É exatamente a janela coberta pelo RPO acima.

## Runbook de ativação

Pré-requisitos: `infra/terraform/envs/primary` aplicado (é dele que o
snapshot é tirado) e `infra/terraform/envs/dr/backend.hcl` configurado
(mesmo bucket de state do primary, key isolada — ver
`infra/terraform/envs/dr/backend.hcl.example`).

```bash
REPO_URL=https://github.com/Kaio4816/tech-challenge-fase-5.git \
  ./scripts/activate-dr.sh
```

O script, em ordem:

1. Lê `rds_instance_id` do output do `envs/primary` e tira um snapshot novo
   do RDS (ou cai para o snapshot mais recente já existente, se o primary
   estiver inacessível).
2. Copia o snapshot cross-region (`us-east-1` → `us-east-2`) e aguarda ficar
   `available` na região de DR.
3. `terraform apply -auto-approve` no `envs/dr`, passando
   `-var snapshot_identifier=<snapshot copiado>` — sobe rede, EKS, RDS
   restaurado (já com o schema e os dados do primary — nenhum `init.sql` é
   reaplicado, diferente do `deploy-primary.sh`), SQS nova e as roles IRSA
   `solidarytech-dr-*`.
4. Configura o `kubectl` para o cluster de DR, cria os Secrets dos 3
   serviços a partir dos outputs do Terraform do `envs/dr`, e instala o
   ArgoCD com `gitops/bootstrap/install.sh dr` (aplica
   `gitops/apps/overlays/dr`, que aponta os 3 serviços para as imagens já
   replicadas no ECR de `us-east-2`).

Ao final, o script imprime o tempo decorrido (snapshot → apply → ArgoCD
aplicado) e lembra de acompanhar `kubectl -n argocd get applications` /
`kubectl -n solidarytech get pods` até tudo ficar `Healthy`/`Ready` — é
nesse ponto que o RTO real termina.

### Verificação (prova de RPO)

```bash
kubectl -n argocd get applications
kubectl -n solidarytech get pods
kubectl -n solidarytech port-forward svc/ngo-service 8081:8081 &
curl localhost:8081/ready

# GET /donations na região de DR deve retornar as doações que já existiam
# no primary antes do failover simulado — essa é a prova de RPO.
```

### Failback (voltar ao primary)

Fora do escopo do ensaio automatizado desta fase (não há `activate-primary.sh`
simétrico). Em uma operação real: restaurar o primary normalmente (ou
`terraform apply` do `envs/primary` do zero, se também tiver sido destruído),
copiar de volta um snapshot atualizado do RDS do DR para `us-east-1`, e
repetir o processo de `deploy-primary.sh`. Como o DR é standby sob demanda
(não fica de pé continuamente), o cenário mais comum no dia a dia do projeto
é simplesmente `terraform destroy` no `envs/dr` depois do ensaio/demo, não um
failback real.

## Limitações conhecidas

- **Dependência do state do primary**: o script lê `rds_instance_id` via
  `terraform output` do `envs/primary`. Isso funciona no ensaio (o primary é
  apenas "perdido" de forma simulada — a instância RDS continua íntegra e
  acessível para o snapshot on-demand) e também numa falha parcial (só os
  serviços/cluster do primary fora do ar, RDS ainda respondendo). Numa falha
  **total** e genuína da região `us-east-1` — incluindo o bucket S3 do state,
  que também vive em `us-east-1` — o script cairia para o fallback do
  snapshot automático mais recente (`describe-db-snapshots`), mas o
  `terraform output` do `rds_instance_id` falharia antes (state remoto
  inacessível nesse cenário limite). **Mitigação implementada**: o
  identificador da instância é estável e conhecido
  (`solidarytech-primary-postgres`), então o script aceita
  `RDS_INSTANCE_ID=solidarytech-primary-postgres ./scripts/activate-dr.sh`,
  que pula completamente a leitura do state do primary. Replicar o bucket de
  state para uma segunda região segue fora do escopo (custo e complexidade
  não justificados para o hackathon).
- **Sem cadência automática de snapshot**: não há um job agendado
  (EventBridge/Lambda ou AWS Backup) tirando snapshots do primary em
  intervalo fixo — o snapshot é sempre tirado on-demand pelo
  `activate-dr.sh`. Isso é suficiente para o RPO ≤ 1h alvo (ver
  justificativa acima) e evita manter automação rodando o tempo todo sobre
  uma instância que também é efêmera; documentado aqui como possível
  hardening futuro, não implementado nesta fase.
- **Sem failback automatizado**: ver seção "Failback" acima.

## Resultado do ensaio

Ensaio completo executado de ponta a ponta contra a conta AWS real em
2026-07-24:

1. `terraform apply` no `envs/primary` (90 recursos) + `deploy-primary.sh` →
   3 Applications `Healthy`/`Synced`.
2. Seed de dados reais: 1 ONG + 2 doações (`id=1` R$50,00, `id=2` R$123,45)
   via `POST /ngos` e `POST /donations` no primary.
3. Primary "perdido" de forma simulada (instância RDS mantida íntegra, só
   não usada como fonte de tráfego) → `REPO_URL=... ./scripts/activate-dr.sh`.
4. **RTO medido: 24min23s** — do início do script (`01:26:57Z`, snapshot
   on-demand) até o último pod dos 3 serviços ficar `Ready` no cluster de DR
   (`01:51:20Z`). Bem abaixo do alvo de 1h e mais rápido que a estimativa de
   ~35–45min (ensaio se beneficiou de um `terraform apply` do EKS mais rápido
   que o histórico e de imagens já replicadas no ECR de `us-east-2`
   antecipadamente).
5. **Prova de RPO confirmada**: `GET /donations` na região de DR
   (`us-east-2`) retornou exatamente as 2 doações criadas no primary
   (mesmos `id`, `amount`, `created_at`) — nenhuma perda de dado transacional.
6. `terraform destroy` limpo em ambas as regiões ao final (31 recursos no
   `envs/dr`, 90 no `envs/primary`), confirmado sem VPC/ENI/RDS/EKS órfãos
   via `aws ec2 describe-network-interfaces` / `describe-vpcs` /
   `rds describe-db-instances` / `eks list-clusters` nas duas regiões.

**Problemas reais encontrados no ensaio (não reintroduzir):**
1. `module.rds.db_instance_id` usava `aws_db_instance.this.id`, que no
   provider AWS atual é o **DbiResourceId** (formato `db-XXXX...`), não o
   identifier legível — `aws rds create-db-snapshot
   --db-instance-identifier` rejeita esse valor. Corrigido usando
   `aws_db_instance.this.identifier` em `modules/rds-postgres/outputs.tf`.
2. Uma queda de rede/DNS local no meio do `terraform destroy` do `envs/dr`
   (bem depois do node group e do RDS já estarem de fato apagados na AWS,
   mas antes do Terraform conseguir salvar o state) deixou o **state lock
   travado no S3** (o `apply` original terminou com `Error acquiring the
   state lock` na tentativa seguinte). Resolvido com
   `terraform force-unlock -force <lock-id>` (seguro porque nenhum outro
   processo estava operando o mesmo state) — o `plan -destroy` seguinte
   detectou corretamente via refresh que node group e RDS já não existiam.
3. O security group do RDS do primary libera a porta 5432 só para o IP de
   quem roda o `terraform apply` (`admin_cidr_blocks`, necessário para o
   provider `postgresql` criar os databases — ver Terraform pós-Fase 3). Se
   esse IP mudar entre o `apply` original e o `destroy` (troca de rede),
   `terraform destroy` falha tentando `DROP DATABASE` com timeout de
   conexão. Precisa rodar `terraform apply -target=module.rds` primeiro
   (recalcula `data.http.my_ip` e atualiza a regra de ingress) antes do
   `destroy` funcionar.
4. Os snapshots manuais criados pelo `activate-dr.sh` (origem em
   `us-east-1` + cópia em `us-east-2`) **não são geridos pelo Terraform** —
   `terraform destroy` não os remove. Precisam ser apagados manualmente
   (`aws rds delete-db-snapshot`) depois do ensaio para não acumular custo
   de armazenamento entre execuções; não implementado como parte do
   `activate-dr.sh` nesta fase (ficaria fora do escopo de "ativar o DR" —
   um snapshot usado no failover pode ser exatamente o que se quer manter
   para investigação pós-incidente).
