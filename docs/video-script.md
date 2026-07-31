# Roteiro do vídeo de demonstração

Objetivo: mostrar cada requisito do edital **funcionando**. A regra de avaliação
é explícita — não basta configurar.

**Duração alvo: 12–15 min.**

> **Como usar este roteiro**: os blocos `> **Falar**` são para serem ditos em voz
> alta, do jeito que estão. São frases curtas de propósito. Não decore: leia uma
> vez antes de gravar, entenda a ideia e fale com suas palavras. Se travar,
> volte para a frase escrita.

> Os números citados são faixas **medidas** contra a AWS real em 25–30/07/2026.
> Na gravação, leia os valores da sua própria tela.
> As evidências estão em [`evidencias/relatorio/`](evidencias/relatorio/) e podem
> ser abertas se a banca pedir.

---

## Painel de acesso (deixe tudo aberto antes de gravar)

### Terminais de port-forward

Um terminal por linha, rodando o vídeo inteiro. Se algum cair, a aba
correspondente para de responder.

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
| **Prometheus — regras** | <http://localhost:9090/rules?search=donation-service> | — |
| **Prometheus — targets** | <http://localhost:9090/targets?search=solidarytech> | — |
| **Alertmanager** | <http://localhost:9093> | — |
| **Repositório** | <https://github.com/Kaio4816/tech-challenge-fase-5> | — |
| **GitHub Actions** | <https://github.com/Kaio4816/tech-challenge-fase-5/actions> | sua conta |
| **PR do Trivy (evidência)** | <https://github.com/Kaio4816/tech-challenge-fase-5/pull/1/checks> | — |
| **SonarCloud** | <https://sonarcloud.io/organizations/kaio4816/projects> | login com GitHub |
| **New Relic — traces** | <https://one.newrelic.com/distributed-tracing> | conta **8324859** |
| **New Relic — condições** | <https://one.newrelic.com/alerts/condition-builder/condition-list> | idem |
| **AWS Tag Editor** | <https://us-east-1.console.aws.amazon.com/resource-groups/tag-editor/find-resources> | filtrar `Project = SolidaryTech` |

Senhas (rode antes e deixe copiadas):

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
- [ ] CI disparada **por um commit real** e verde (o ECR nasce vazio a cada
      apply; sem isso os pods ficam em `ImagePullBackOff`).
- [ ] `./scripts/deploy-primary.sh` **com** `NEW_RELIC_LICENSE_KEY` definida.
- [ ] `kubectl -n argocd get applications` → **9 Applications** `Synced`/`Healthy`.
- [ ] Dados de seed criados (1 ONG + doações + 1 voluntário).
- [ ] `hey` e `jq` instalados (`brew install hey jq`).
- [ ] **Teste de carga rodando** antes de abrir o Grafana, senão os gráficos
      aparecem chapados: `NGO_ID=3 ./scripts/load-test.sh 60m 8`
- [ ] ⚠️ **Um gerador de carga por vez.** O `mttr-drill.sh` sobe o seu próprio
      `load-test.sh`. Se o teste acima ainda estiver rodando quando você disparar
      o drill, a concorrência dobra, o `db.t4g.micro` satura e a linha de base do
      p95 passa dos 300 ms — aí o alerta de latência mede a sua carga, não o
      incidente. Antes do drill: `pkill -f "hey -z"` e espere o p95 cair.
- [ ] **Tags de alocação de custo ativadas em Billing** — leva até 24h. Se não
      deu tempo, use o Tag Editor, que é imediato.
- [ ] `pkill -f port-forward` e reabra os túneis (túnel velho aponta para pod
      que já morreu).
- [ ] Abas abertas e logadas conforme a tabela acima.

---

## Bloco 1 — Abertura e arquitetura (1 min)

**Na tela**: [`architecture.md`](architecture.md), o primeiro diagrama. Depois a
raiz do repositório com `apps/`, `infra/`, `gitops/`, `docs/`.

> **Falar**: "Oi. Eu sou o Kaio Henrique, RM367900.
>
> O desafio era pegar três microsserviços de uma ONG fictícia, a SolidaryTech, e
> transformar isso num ecossistema completo. A diretoria pediu quatro coisas: que
> as doações não parem nem se a nuvem falhar, custo controlado, resposta rápida a
> problema, e metas de disponibilidade claras.
>
> Esse diagrama é a solução inteira. Vou percorrer ele rápido."

**Percurso do cursor**: GitHub → Actions → ECR → seta de volta pro GitHub →
ArgoCD → namespace `solidarytech` → `donation-service` → seta pro `ngo-service`
→ RDS/SQS/DynamoDB → namespace `monitoring` → New Relic.

> **Falar**: "Aqui na esquerda, o código no GitHub. Qualquer commit dispara a
> esteira: teste, análise de segurança, build, scan de imagem.
>
> A esteira entrega duas coisas. Uma imagem no ECR, e um commit de volta no
> próprio Git. Repara: a esteira não encosta no cluster.
>
> Quem encosta no cluster é o ArgoCD, aqui dentro do EKS. Ele fica olhando o Git
> e aplica o que mudou.
>
> Esses são os três serviços. Esse aqui, o `donation-service`, em Go, é o que eu
> chamo de Hot Path. É o caminho crítico, é onde a doação acontece. Ele é o único
> com escalonamento automático e é o alvo das metas de disponibilidade.
>
> E essa seta aqui é importante: antes de gravar a doação, ele consulta o
> `ngo-service`. Guarda isso, porque essa seta volta duas vezes no vídeo.
>
> Os dados ficam fora do cluster, em serviços gerenciados. Postgres, fila e
> DynamoDB, todos criados por Terraform.
>
> E embaixo a parte de monitoramento: Prometheus, Grafana, Loki, e o New Relic
> recebendo os rastros das requisições."

> **Frase de fechamento**: "O `donation-service` é o Hot Path. Tudo que vem
> depois gira em torno de manter esse caminho de pé."

## Bloco 2 — Fundação: Docker, Terraform, EKS (2 min)

**Na tela, nesta ordem**:

1. `apps/donation-service/Dockerfile`
2. `infra/terraform/modules/` e depois `modules/eks/main.tf`
3. Terminal

> **Falar** (no Dockerfile): "Build em duas etapas. Em cima eu compilo o Go. Em
> baixo, a imagem final: `distroless`. Ela não tem shell, não tem gerenciador de
> pacote, não tem nada. Só o binário. Se alguém invadir esse container, não tem
> nem `sh` para rodar comando."

> **Falar** (nos módulos): "Sete módulos Terraform: rede, cluster, banco, fila,
> tabela, registro de imagem e as permissões. Os mesmos módulos servem as duas
> regiões, a principal e a de contingência. Aqui no módulo do cluster, olha o
> tipo de instância: **Spot**. É 70% mais barato que sob demanda."

```bash
kubectl get nodes -o wide
kubectl -n solidarytech get pods
```

> **Falar**: "E aqui está de pé. Os nós prontos, os três serviços rodando."

> **Frase de fechamento**: "Nada disso foi criado no console da AWS. Cluster,
> banco, fila e tabela saem todos de um `terraform apply`."

## Bloco 3 — CI/CD e DevSecOps (3 min)

**Na tela**: <https://github.com/Kaio4816/tech-challenge-fase-5/actions>

### 3.1 — A esteira completa

Abra uma run filtrando por **Event: push**. Não pegue a mais recente sem olhar:
rerun manual deixa os dois últimos jobs cinza de propósito, e é justamente o fim
da esteira que interessa.

> **Falar**: "Essa é a esteira do `donation-service`, rodando de verdade. Oito
> etapas, todas verdes.
>
> Teste com cobertura. Depois análise estática do código, procurando falha de
> segurança. SonarCloud, que é a qualidade. Análise das dependências, procurando
> biblioteca vulnerável. Aí builda a imagem, escaneia a imagem, envia pro
> registro da AWS, e por último atualiza o Git."

### 3.2 — O portão de segurança

**Onde exatamente**: abra `.github/workflows/ci-donation-service.yml` no editor.
O job do Trivy começa na **linha 144** (`scan-image:`) e as três linhas que você
aponta são a **168, 169 e 170**.

> ⚠️ Existe outro bloco com essas mesmas três linhas, nas **115–117**. Aquele é o
> job `sca`, que escaneia as **dependências do código**. O que você quer é o das
> 168–170, que escaneia a **imagem**. Apontar o errado desalinha a narrativa.

> **Falar** (com as linhas 168–170 na tela): "Esse job aqui é um portão. Três
> linhas definem ele.
>
> A primeira diz que só conta vulnerabilidade alta ou crítica. A segunda faz o
> comando falhar quando encontra alguma. E a terceira ignora o que não tem
> correção disponível — porque bloquear por algo que ninguém consegue arrumar só
> ensina o time a ignorar o alerta.
>
> Agora, numa esteira verde esse job não prova nada. Ele mostra zero
> vulnerabilidade e pronto. Então eu preparei uma prova."

Abrir o **PR #1** → aba **Checks**.

> **Falar**: "Esse pull request muda uma linha só: a imagem base do serviço, para
> uma versão velha e vulnerável de propósito. O código Go é idêntico.
>
> Olha o resultado. Teste passou. Análise de segurança passou. Sonar passou.
> Build passou. E o Trivy **falhou**: achou uma vulnerabilidade crítica, com
> correção disponível.
>
> E o mais importante são esses dois aqui embaixo, em cinza: enviar pro registro
> e atualizar o Git. Eles **nem rodaram**. A imagem vulnerável não chegou no
> registro, muito menos no cluster."

> ⚠️ **Não diga que o merge está bloqueado.** No topo da página o GitHub mostra
> **"Able to merge"** com check verde, porque a `main` não tem regra de proteção
> exigindo os checks. Se você afirmar bloqueio de merge, a própria tela contradiz.
> Fale só do que é verificável: o Trivy falhou e os dois jobs seguintes não
> rodaram.
>
> Se quiser transformar em ponto a favor: *"o merge aqui ainda está liberado
> porque eu não ativei proteção de branch neste repositório. Mas repara que isso
> não muda o resultado: mesmo que alguém mergeasse, a imagem vulnerável não existe
> no registro, porque o job que publica nunca rodou."*

**Antes de abrir os Checks**: clique na setinha `>` ao lado de **"CI -
donation-service"**, na coluna da esquerda, para expandir os 8 jobs. Sem isso a
tela abre no SonarCloud, que está verde e não é o ponto.

### 3.3 — Sem senha guardada

**Onde exatamente**: no mesmo arquivo, o job `push` começa na **linha 172**. Duas
linhas importam:

- **182** — `id-token: write`. É a permissão que deixa o GitHub emitir o token de
  identidade. Sem ela, a autenticação sem senha não acontece.
- **198** — `role-to-assume: ${{ vars.AWS_ECR_ROLE_ARN }}`. Aqui o que você aponta
  é a **ausência**: não existe `aws-access-key-id` nem `aws-secret-access-key`.

> **Falar**: "Um detalhe de segurança. Para enviar a imagem pra AWS não existe
> chave de acesso nenhuma guardada no GitHub. A autenticação é por OIDC: o GitHub
> prova quem ele é, e a AWS entrega um crachá temporário. Não tem senha para
> vazar."

**A prova que fecha o argumento** (rode na câmera, é mais forte que o YAML):

```bash
gh secret list
gh variable list
```

Saída esperada: **um único segredo no repositório inteiro**, o `SONAR_TOKEN`. E o
`AWS_ECR_ROLE_ARN` aparece em *variables*, não em *secrets*.

> **Falar**: "Repara que o endereço do papel da AWS está em variáveis, não em
> segredos. Porque ele não é segredo: saber o endereço não dá acesso a nada. Quem
> autoriza é a política de confiança do lado da AWS, que só aceita token vindo
> deste repositório."

### 3.4 — SonarCloud

Abrir <https://sonarcloud.io/organizations/kaio4816/projects>.

> **Falar**: "O edital pede SonarQube. Eu usei o SonarCloud, que é o mesmo motor
> entregue como serviço, de graça para repositório público.
>
> Um projeto por microsserviço, os três aprovados no quality gate. Zero bug.
>
> E aqui eu preciso ser honesto: a cobertura de teste do `donation-service` é
> 25%, enquanto os dois em Python estão em 80%. O que está coberto é a regra de
> negócio da doação. O que não está é integração — banco, fila, a chamada pro
> outro serviço. Isso eu cubro com o `readiness probe` e com os alertas em
> produção, não com teste unitário. É uma dívida que eu conheço."

### 3.5 — O commit que a esteira escreveu

Abrir <https://github.com/Kaio4816/tech-challenge-fase-5/commit/4687cd2>.

> **Falar**: "Esse é o último passo, e é o que explica o desenho todo. A esteira
> não faz deploy. Ela faz um commit.
>
> Olha o autor: `github-actions[bot]`. Nenhuma pessoa digitou isso.
>
> E olha o tamanho: um arquivo, uma linha. Ela trocou a tag da imagem para o
> código que acabou de construir.
>
> Esse `[skip ci]` no final da mensagem evita laço infinito: sem ele, esse commit
> dispararia a esteira de novo, que faria outro commit, e não parava mais."

> **Frase de fechamento**: "A esteira não faz deploy. Ela mexe no Git. Quem faz
> deploy é o ArgoCD. Guarda esse código aqui, `7504328`, que ele reaparece agora."

## Bloco 4 — GitOps ponta a ponta (2 min)

**Na tela**: <https://localhost:8080> (ArgoCD)

> **Falar**: "Aqui está o ArgoCD. Nove aplicações, todas `Synced` e `Healthy`.
> Nenhuma fora de sincronia.
>
> Essa aqui, a `solidarytech-root`, é a raiz. Ela não sobe nada sozinha: ela
> **gera** as outras oito. É o padrão app-of-apps. Se eu adicionar um serviço
> novo no Git, ele aparece aqui sem eu tocar em nada.
>
> E repara na revisão sincronizada: é aquele mesmo código que a esteira commitou
> há pouco. Os dois lados do ciclo se encontram aqui."

**Self-heal ao vivo**:

```bash
kubectl -n solidarytech scale deploy/volunteer-service --replicas=3
kubectl -n solidarytech get pods -l app.kubernetes.io/name=volunteer-service -w
```

> **Falar**: "Agora eu vou fazer o que não se deve fazer: mexer no cluster na
> mão. Vou subir esse serviço de uma para três réplicas.
>
> Subiu. Três pods.
>
> E agora o ArgoCD percebe que o cluster está diferente do Git, e desfaz. Volta
> pra uma réplica. Eu não digitei nada.
>
> Esse laço foi medido em **37 segundos** no ensaio que eu vou mostrar daqui a
> pouco."

> **Frase de fechamento**: "O estado desejado está no Git. Qualquer divergência é
> revertida sozinha."

## Bloco 5 — O produto funcionando (1 min)

> **Falar**: "Até aqui foi esteira e plataforma. Agora o produto. São três
> chamadas, e cada uma toca um banco diferente."

```bash
NGO_ID=$(curl -sS -X POST localhost:8081/ngos -H 'Content-Type: application/json' \
  -d '{"name":"ONG Demo","email":"demo@ong.org","cause":"Educacao","city":"Sao Paulo"}' \
  | jq -r .id)
echo "ONG criada com id $NGO_ID"
```

> **Falar**: "Primeiro, cadastro de uma ONG. Isso vai pro Postgres. Estou
> guardando o id numa variável porque a próxima chamada precisa dele."

> ⚠️ **Não use `"ngo_id": 1` fixo.** A tabela já tem registros e o contador nunca
> recua, então a ONG criada na gravação não será a de id 1.

```bash
curl -sS -X POST localhost:8082/donations -H 'Content-Type: application/json' \
  -d "{\"ngo_id\": $NGO_ID, \"amount\": 250.00, \"donor_name\": \"Doador Demo\"}"
```

> **Falar**: "Agora a doação. Esse é o Hot Path. Ele valida a ONG chamando o
> outro serviço, grava no banco, e só **depois** de gravar publica um evento na
> fila.
>
> Essa ordem é de propósito: a doação existe antes da notificação. Isso volta no
> bloco de contingência."

```bash
curl -sS -X POST localhost:8083/volunteers -H 'Content-Type: application/json' \
  -d "{\"name\":\"Voluntario Demo\",\"email\":\"vol@demo.org\",\"ngo_id\": $NGO_ID}"
```

> **Falar**: "E um voluntário, que vai pro DynamoDB. Banco diferente, de
> propósito."

```bash
aws dynamodb scan --table-name SolidaryTechVolunteers --region us-east-1 \
  --query 'Items[].{nome:name.S,email:email.S}'
```

> **Falar**: "E aqui está ele, consultado direto na AWS. Não é a aplicação me
> dizendo que gravou. É o banco confirmando.
>
> E o detalhe de segurança: pra escrever isso, o pod não tem chave de acesso
> nenhuma. Nem variável de ambiente, nem arquivo. Ele assume uma permissão da AWS
> usando a identidade dele no Kubernetes. Se invadirem o container, não tem
> credencial pra roubar."

> ⚠️ Se você ensaiar este bloco, o e-mail `demo@ong.org` fica ocupado e a segunda
> tentativa devolve erro 409. Troque o e-mail ou apague o registro antes.

## Bloco 6 — Observabilidade e SRE (3 min)

> ⏱ **Dispare o ensaio de MTTR num terminal separado ANTES deste bloco.** A
> detecção leva de 6 a 9 minutos e você volta nele no bloco 7. (Se for gravar
> pela opção B — narrar a linha do tempo já pronta — veja as instruções no
> começo do bloco 7.)
>
> **Mate a carga do checklist primeiro** — o drill sobe a sua própria, e duas
> juntas saturam o banco (foi o que invalidou a linha de base na rodada de 30/07):
> ```bash
> pkill -f "hey -z"
> # espere o p95 cair (uns 2 min) e confira:
> curl -s -G --data-urlencode 'query=histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="donation-service",path="/donations"}[2m])) by (le))' \
>   http://localhost:9090/api/v1/query | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print(round(float(r[0]['value'][1])*1000,1),'ms') if r else print('sem trafego')"
>
> NGO_ID=3 BASELINE_SECS=120 ./scripts/mttr-drill.sh detect 18m 8
> ```
> O drill **aborta sozinho** se detectar outra carga rodando ou se a linha de base
> do p95 passar de 300 ms — e imprime o comando com a concorrência já reduzida pela
> metade. Se isso acontecer, é só copiar o que ele sugere e rodar de novo.

### 6.1 — As metas

Abrir [`sre-slo.md`](sre-slo.md).

> **Falar**: "SRE começa decidindo o que significa 'funcionando'. Eu defini dois
> indicadores para o Hot Path.
>
> Disponibilidade: quantas doações não deram erro. E latência: quanto tempo o p95
> das requisições leva.
>
> O contrato com as ONGs é 99,5% no mês. Mas a minha meta interna é **99,9%**,
> mais apertada de propósito. Essa folga entre as duas é o tempo que eu tenho pra
> agir antes de furar o contrato.
>
> E 99,9% no mês vira um número bem concreto: **43 minutos**. Esse é o orçamento
> de erro. É quanto o serviço pode ficar ruim no mês. Não é meta de perfeição, é
> orçamento. E orçamento existe pra ser gasto: enquanto sobra, dá pra arriscar
> deploy. Quando acaba, a prioridade vira estabilidade."

### 6.2 — O dashboard

Grafana → *"SolidaryTech - SRE Golden Metrics & SLO"*.

> **Falar**: "Esse painel é código. É um arquivo no Git aplicado pelo ArgoCD, não
> algo que eu desenhei clicando. Se o cluster for destruído e recriado, ele volta
> igual.
>
> Aqui em cima o volume de requisições, subindo porque tem um teste de carga
> rodando agora. Do lado, a taxa de erro. E as latências: p50, p95 e p99.
>
> Os três juntos porque a média mente. Dá pra ter média ótima e 5% dos doadores
> esperando dois segundos.
>
> E aqui embaixo é o que traduz tudo pra linguagem de negócio: disponibilidade em
> 100%, orçamento de erro intacto, e a velocidade de consumo em zero."

### 6.3 — As regras

Prometheus → <http://localhost:9090/rules?search=donation-service>

> **Falar**: "São essas regras que alimentam aquilo. Elas implementam o que o
> Google chama de multi-burn-rate.
>
> A ideia é simples: se o orçamento do mês está sendo gasto 14 vezes mais rápido
> que o sustentável, ele acaba em dois dias. Isso é alerta crítico, acorda alguém.
> Se está 6 vezes mais rápido, é aviso, vira tarefa pro dia seguinte.
>
> E cada um olha duas janelas de tempo ao mesmo tempo, uma curta e uma longa. É
> pra não gritar por um pico de 30 segundos, e ao mesmo tempo não demorar meia
> hora pra perceber uma queda de verdade."

### 6.4 — Rastreamento distribuído

New Relic → <https://one.newrelic.com/distributed-tracing>

> **Falar**: "Métrica diz que está lento. Rastro diz **onde**.
>
> Esse é um `POST /donations` de verdade. Olha esse mapa: o `donation-service`
> chamando o `ngo-service`.
>
> E aqui embaixo a linha do tempo. O de cima é o Go, 48 milissegundos. E dentro
> dele tem esse filho, de 2 milissegundos, que está rodando **no outro serviço**,
> em Python.
>
> Dois processos, duas linguagens, dois pods. Um rastro só.
>
> E isso não veio de graça. O OpenTelemetry em Go vem com o propagador desligado
> por padrão. Sem ligar ele, os rastros chegam, os dois serviços aparecem, mas
> separados. Foi um bug real que eu só achei olhando essa tela."

### 6.5 — Logs

Grafana → *Explore* → datasource **Loki** → `{namespace="solidarytech"}`

> **Falar**: "E o terceiro pilar: os logs dos três serviços num lugar só.
> Métrica, rastro e log na mesma ferramenta. Quem está de plantão não fica
> trocando de aba no meio de um incidente."

> **Frase de fechamento**: "A meta interna é mais apertada que o contrato de
> propósito. Essa folga é o tempo que a gente tem pra agir."

## Bloco 7 — Um incidente do início ao fim (2,5 min) ⭐

> 📍 **Posição no vídeo final**: este bloco entra **depois dos blocos 8, 9 e 10**,
> logo antes do encerramento. As falas abaixo já assumem isso — elas fazem a ponte
> a partir do bloco de continuidade e entregam no encerramento. Se você decidir
> voltar para a ordem numérica na edição, troque a frase de abertura e a de
> fechamento pelas alternativas marcadas *(ordem numérica)*.

**Como gravar**: rode o ensaio **antes** e deixe terminar (leva ~10 min de
relógio, com ~9 minutos de espera até o alerta). Grave os blocos 8, 9 e 10 nessa
janela e volte aqui no fim, narrando numa tomada só a linha do tempo que ficou no
terminal. Sem tempo morto, sem corte na edição.

```bash
NGO_ID=3 BASELINE_SECS=120 ./scripts/mttr-drill.sh detect 18m 8
```

Enquanto ele roda, grave os blocos 8, 9 e 10 — nenhum depende do ensaio, e a
carga que o drill sobe faz o `kubectl top pods` do bloco 8 mostrar consumo real.

**Duas telas no bloco 7**:

1. O **terminal** com a linha do tempo completa (é a evidência principal — tem
   carimbo de hora em cada marco).
2. O **Grafana**, no dashboard SRE, janela de 1 hora: o pico de latência **fica
   no histórico** e continua visível depois que tudo normalizou.

> ⚠️ Quando você gravar, o alerta já terá resolvido, então `localhost:9090/alerts`
> **não** vai mostrar `DonationServiceHighLatencyP95` em vermelho. Não abra essa
> tela prometendo o vermelho. A prova está no carimbo de hora do `ALERTA_FIRING`
> no terminal e no pico do gráfico. Se quiser o vermelho ao vivo, é a opção de
> gravar durante o ensaio — mas aí vêm os ~9 minutos de espera junto.

> **Falar**: "Eu acabei de mostrar o plano para o pior caso: uma região inteira
> caindo. Agora o caso comum — uma falha pequena, num serviço só, do início ao
> fim. E com cronômetro.
>
> Lembra daquele ciclo que eu mostrei há pouco? Detecção, alerta, tratamento,
> post-mortem. Isso aqui é ele acontecendo de verdade.
>
> O incidente é realista: eu derrubei o `ngo-service`, que é a dependência do
> caminho crítico. Aquela seta lá do começo do vídeo. Isso aqui é o resultado."

> *(ordem numérica — se o bloco vier logo depois do 6)*: "Tudo que eu mostrei está
> de pé e saudável. Então eu quebrei de propósito, com cronômetro. O incidente é
> realista: derrubei o `ngo-service`, a dependência do caminho crítico. Aquela seta
> do começo do vídeo. Isso aqui é o resultado."

> ✅ **O drill valida a própria medição.** Se a linha de base do p95 já estiver
> acima dos 300 ms do SLO, ele **aborta** com instrução de reduzir a concorrência,
> em vez de seguir e produzir um número que parece válido e não é. Ou seja: se o
> ensaio chegou até o fim, a medição é confiável. Isso vale citar em uma frase.

**Sete paradas, na ordem em que a linha do tempo aparece.** Cada parada tem o
rótulo **exatamente como está na tela** e a fala correspondente. Os pontos que
valem nota já estão embutidos onde eles surgem naturalmente — não há discurso
separado no fim.

---

**① `BASELINE_P95_MS 14`**

> "Antes de quebrar qualquer coisa, o script mede a linha de base e compara com o
> meu limite. Deu **14 milissegundos**, contra um SLO de 300. Medição válida.
>
> E essa verificação existe porque um ensaio anterior deu errado: a minha própria
> carga de teste estava saturando o banco, e a latência já estava em 352
> milissegundos **antes** da falha. O alerta disparou, mas estava medindo o
> gerador de carga, não o incidente. O número parecia perfeitamente válido.
>
> Medição que não sabe dizer quando está inválida é pior que não medir. Hoje o
> ensaio se recusa a rodar nessa condição."

---

**② `T0_INICIO_IMPACTO` → `FALHA_EFETIVA (+3s)`**

> "Aqui começa o incidente: derrubei a dependência para zero réplicas. E em **3
> segundos** o script confirma que ela saiu do ar de verdade — ele não confia no
> comando, ele verifica."

---

**③ `DEGRADACAO_P95 p95=898ms (+65s)`**

> "**Sessenta e cinco segundos** depois, a latência sai de 14 milissegundos e vai
> para **898**. É o Hot Path esperando o timeout da dependência."

---

**④ Alterne para o terminal do `curl`** — este é o ponto mais importante do bloco

```bash
curl -sS localhost:8082/donations | tail -c 300
```

> "E agora o que realmente importa: **nenhuma doação falhou**. Com a dependência
> fora do ar, o serviço continua gravando normalmente.
>
> Porque a validação é *fail-open*: se o outro serviço cai, a doação é registrada
> mesmo assim. Só um 'ONG não existe' explícito rejeita.
>
> E olha o efeito disso: a dependência caiu e **não gerou erro nenhum**. Gerou
> lentidão.
>
> Isso muda tudo, porque o meu orçamento de erro conta falha. Não conta demora.
> Então esse incidente inteiro não gastou nada dele. Saiu zerado.
>
> E aí mora uma armadilha: quem for investigar isso procurando erro não vai achar
> nada. Vai procurar no lugar errado. Foi por isso que eu escrevi isso no runbook."

*Alternativa, se preferir não usar o terminal*: o painel **Errors** do dashboard
SRE em 0% durante todo o incidente prova a mesma coisa e é mais visual.

<details>
<summary><b>⚠️ Se o comando devolver vazio — leia antes de gravar</b></summary>

**Use `-sS`, não `-s`.** O `-s` engole erro de conexão: com o túnel caído a saída
vem vazia e parece banco sem doações — o oposto do que você quer provar.

**Rode este `curl` antes de disparar carga nova.** `GET /donations` faz `SELECT`
sem `LIMIT` (`apps/donation-service/main.go:262`). Depois de um teste de carga o
banco fica com centenas de milhares de linhas, o endpoint carrega tudo na memória,
estoura os 128Mi do container e o pod é **`OOMKilled`** — a conexão fecha e o
`curl` volta vazio. Ocorreu em 31/07 com 355.901 linhas.

Limpeza (mantém as doações de demonstração):

```bash
kubectl -n solidarytech exec deploy/ngo-service -- python3 -c "
import os,psycopg2
u=os.environ['DATABASE_URL'].replace('ngo_db','donation_db')
c=psycopg2.connect(u); cur=c.cursor()
cur.execute(\"DELETE FROM donations WHERE donor_name = 'Load Test'\"); c.commit()
cur.execute('SELECT count(*) FROM donations'); print('restaram:', cur.fetchone()[0])"
```

</details>

---

**⑤ `ALERTA_FIRING (+519s)` → `T1_DETECCAO MTTD=520s`**

> "**519 segundos** até o alerta disparar, e o script fecha a conta: **MTTD de 520
> segundos**. Esse é o tempo de detecção."

---

**⑥ `LIBERACAO` → `T3_RECUPERADO (+677)s` → `P95_FINAL_MS 14`**

> "Aqui eu solto o incidente e paro de segurar. Daqui pra frente é o ArgoCD.
>
> E recuperou aos **677 segundos**, sem eu digitar nada. É o self-heal: o estado
> desejado está no Git, o cluster divergiu, e ele desfez a divergência sozinho.
>
> E a latência voltou a **14 milissegundos** — exatamente o número da linha de
> base. O sistema fechou o ciclo sozinho."

---

**⑦ O resumo do rodapé** — aponte estas quatro linhas:

```
MTTD = 520s
Serviço recuperado em +677s
Holder liberado (selfHeal assume) em +520s
MTTR = 847s (meta: < 300s)
```

> "E aqui o script diz que o MTTR total deu **847 segundos**, acima da minha meta
> de 300. Preciso explicar esse número, porque ele é enganoso.
>
> Olha essas duas linhas: o holder foi liberado aos **520 segundos** e o serviço
> recuperou aos **677**. A diferença é **157 segundos** — foi isso que a
> recuperação levou de fato. Dentro da meta.
>
> O resto do total são os 8 minutos e meio em que eu **segurei a falha de
> propósito**, para o alerta ter tempo de disparar. Se eu soltasse antes, ele nem
> chegaria a disparar e eu não teria o que mostrar.
>
> E aí está o achado mais interessante, que é meio desconfortável: **detectar levou
> 520 segundos, corrigir levou 157**. A correção é mais de três vezes mais rápida
> que a detecção.
>
> Ou seja, sem eu segurar o incidente, o sistema **se curaria antes de perceber que
> estava doente**. Ótimo pro usuário, péssimo pra quem opera — falha que não deixa
> rastro é falha que se repete.
>
> Eu não descobri isso no papel. Descobri rodando. E virou ação corretiva no
> post-mortem, com dono."

---

> ℹ️ **Os tempos variam entre rodadas.** Já medi recuperação de 37 s, 157 s e
> 196 s, e detecção de 373 s, 424 s e 520 s — depende de quanto o agendador demora
> a colocar o pod num nó e de onde a janela de 5 min da métrica cai. **Leia os
> números da sua tela.** O que é constante é que ninguém intervém e que detectar
> leva mais tempo que corrigir.

> ℹ️ **Se abrir a tela de alertas, explique o que já está vermelho lá.** O
> kube-prometheus-stack traz dezenas de regras próprias, e 4 ficam permanentemente
> em firing neste cluster. Nenhuma é do projeto — vale citar, porque a banca vai
> ver:
>
> - **`Watchdog`** e **`InfoInhibitor`**: disparam *sempre*, por desenho. O
>   Watchdog prova que o pipeline de alertas está vivo; por isso o nosso
>   Alertmanager manda ele para um receiver nulo (volta no bloco 9).
> - **`KubeHpaMaxedOut`**: legítimo e a favor — o HPA do `donation-service` está no
>   teto de 4 réplicas por causa da carga. É a prova de que ele escalou.
> - **`CPUThrottlingHigh`** (severidade `info`): containers do node-exporter sendo
>   limitados. Ruído conhecido de cluster pequeno.
>
> Para mostrar só os do projeto, use o campo **"Filter by rule name or labels"** e
> digite `Donation`.

> ⚠️ **Não prometa o que não vai acontecer**: `SolidaryTechTargetDown` **não**
> dispara nesse cenário (com zero réplicas a série `up` desaparece, e ausência não
> satisfaz `== 0`), e **não haverá e-mail do New Relic** — o roteamento automático
> é bloqueado no plano gratuito. Citar como achado é mais forte do que omitir e ser
> perguntado.

> ⚠️ **Pré-requisito da rodada válida**: um único gerador de carga. O drill sobe o
> seu próprio, então mate qualquer carga anterior antes (`pkill -f "hey -z"`) e
> espere o p95 cair. O script verifica isso e recusa rodar se houver outra carga
> ativa — ver a nota no início do bloco 6. Se ele abortar por linha de base alta,
> copie o comando que ele mesmo imprime, já com a concorrência reduzida.

> **Frase de fechamento**: "Detectamos em 520 segundos e recuperamos em 157, sem
> ninguém intervir. E o ensaio mostrou o gargalo real: é a detecção, não
> a correção.
>
> Com isso o ciclo fecha: falha, detecção, alerta, recuperação e post-mortem — os
> cinco estágios que eu mostrei no diagrama, agora cronometrados. Só me resta
> derrubar tudo."
>
> *(ordem numérica)*: encerre em "…é a detecção, não a correção." e siga para o
> bloco 8.

## Bloco 8 — FinOps (1,5 min)

> **Falar**: "Controlar custo aqui não é enfeite. O cliente é uma ONG. Cada dólar
> que vai pra infraestrutura é um dólar que não vira projeto social."

**Na tela**: `infra/terraform/envs/primary/providers.tf`

> **Falar**: "Governança de custo começa sabendo de quem é a conta. Essas três
> etiquetas ficam na configuração do provedor. Isso significa que **todo** recurso
> que o Terraform criar já nasce etiquetado, sem ninguém precisar lembrar. E não
> existe caminho pra criar recurso sem etiqueta, porque não existe caminho pra
> criar recurso fora do Terraform."

**AWS Tag Editor** → filtrar `Project = SolidaryTech`

> **Falar**: "E aqui a prova. Cluster, banco, fila, tabela, rede — tudo com a
> mesma etiqueta, tudo rastreável por centro de custo.
>
> Sendo honesto: alguns tipos de recurso a AWS simplesmente não deixa etiquetar.
> Não é falha de cobertura, é limitação da plataforma, e está documentado."

**Abrir** [`finops-forecast.md`](finops-forecast.md)

> **Falar**: "A previsão é linha a linha. Dá **171 dólares por mês** se ficasse
> ligado o tempo todo.
>
> E o maior item nem é computação: são 73 dólares só do painel de controle do
> Kubernetes, que é preço fixo da AWS.
>
> Agora as decisões que derrubaram esse número. Máquinas Spot, 70% mais baratas.
> Um gateway de saída em vez de um por zona. Uma instância de banco com dois
> bancos dentro, em vez de duas instâncias. Nenhum balanceador de carga — as demos
> usam túnel, o que economiza 20 dólares por mês.
>
> E a maior de todas: o ambiente de contingência **só existe quando precisa**.
> Isso elimina 145 dólares por mês de coisa parada esperando um desastre."

```bash
kubectl -n solidarytech top pods
```

> ⏱ Para o consumo aparecer **sob carga**, grave este trecho enquanto a carga do
> drill (18 min) ainda roda. Se já tiver acabado, suba uma antes:
> `NGO_ID=3 ./scripts/load-test.sh 20m 8`. Sem carga os números ficam em 1–2
> milicores e o argumento de dimensionamento perde força.

> **Falar**: "E dimensionamento com dado, não com chute. Esse é o consumo real
> sob carga, pra comparar com o que eu reservei.
>
> Aliás, o achado mais estranho do projeto: o limite do meu cluster não era
> processador nem memória. Era **quantidade de pods por máquina**. A rede da AWS
> distribui endereços por placa, e esse tipo de máquina só comporta 17 pods. Eu
> bati o teto com o processador em 50%. Qualquer painel de recurso mostraria o
> cluster folgado."

> **Frase de fechamento**: "Cada linha dessa conta tem uma decisão de engenharia
> atrás."

## Bloco 9 — Gestão de incidentes e AIOps (1,5 min)

**Na tela**: [`itsm-incident-flow.md`](itsm-incident-flow.md)

**Percurso**: caixas 1 → 5, e **por último** a seta pontilhada.

> **Falar**: "Daqui a pouco eu vou mostrar um incidente do início ao fim, com
> cronômetro. Antes disso, o processo que ele percorre — porque incidente não é
> evento solto. Cada caixa aqui aponta pra um arquivo que existe no repositório.
>
> Detecção em três camadas. O Prometheus pega violação de contrato. O New Relic
> pega desvio do normal. E o Kubernetes pega pod morto, em segundos.
>
> Alerta: o Alertmanager agrupa e remove duplicado. Tratamento: tem um runbook com
> árvore de decisão. Depois post-mortem em 48 horas, e comunicação, com modelos de
> e-mail prontos pra diretoria e pras ONGs.
>
> Mas a seta mais importante é essa pontilhada aqui: **a maior parte das falhas
> nunca vira incidente**. Sonda, autocorreção e escalonamento resolvem sozinhos.
>
> A forma mais eficaz de reduzir tempo de recuperação não é responder mais rápido.
> É fazer com que não tenha o que responder."

**Na tela**: `infra/terraform/newrelic/main.tf`

Cinco paradas no arquivo. Role de uma para a outra falando — cada parada é uma
frase curta, não um parágrafo.

---

**① Vá para a linha 66** e deixe na tela `type = "static"`.

> "Essa é uma condição de alerta comum. Olha o tipo: **estático**. O limiar sou
> eu que escolhi — 300 milissegundos, porque eu decidi que 300 é o meu limite."

---

**② Role até a linha 134**, `type = "baseline"`. Deixe as duas visíveis se couber.

> "Agora essa. Mesmo tipo de recurso, mas o tipo é **baseline**. Aqui eu não digo
> o número. O New Relic aprende como o serviço se comporta e avisa quando ele foge
> do padrão.
>
> A diferença prática: alerta comum só existe **depois** que já teve erro. O
> baseline dispara quando o comportamento **muda** — mesmo sem erro nenhum."

---

**③ Desça 12 linhas, até a 146**, `baseline_direction = "upper_and_lower"`.

> "E repara nessa: eu monitoro desvio nos **dois** sentidos.
>
> Pico é óbvio. Mas **queda** de doações é o pior cenário para uma ONG, e é
> invisível para qualquer alerta de erro — porque não tem erro. Simplesmente parou
> de chegar dinheiro."

---

**④ Linha 147**, logo abaixo: `signal_seasonality = "NEW_RELIC_CALCULATION"`.

> "E essa aqui é o 'aprende' literal. É o parâmetro que manda a ferramenta
> calcular a sazonalidade do sinal."

---

**⑤ Linha 155**, a consulta.

> "E o dado vem de `Span`. Não tem agente de APM instalado: é o mesmo OTLP que
> gera o rastreamento distribuído. Uma instrumentação só, servindo para o trace e
> para a detecção de anomalia."

---

**Feche o arquivo com esta frase**, que é a que amarra o bloco:

> "E tudo isso é Terraform, não configuração clicada. Alerta configurado na mão é
> alerta que se perde no próximo ambiente."

> 💡 **Se sobrar tempo**: as linhas **136–141** são a descrição da condição,
> escrita em português dentro do próprio código, explicando por que
> `upper_and_lower`. Um segundo de tela — mostra que a decisão está documentada
> onde é aplicada, não num wiki à parte.

---

**Agora troque para o New Relic**:
<https://one.newrelic.com/alerts/condition-builder/condition-list>

Aponte a **coluna `Type`**.

> "E aplicado na conta: cinco condições. Duas são **NRQL Baseline**, três são
> limiar fixo. É o mesmo contraste que eu acabei de mostrar no código, agora
> rodando de verdade."

> **Frase de fechamento**: "Detecção preditiva é o limiar aprendido, não o limiar
> fixo. Ele dispara quando o comportamento muda, antes de a meta ser violada."

## Bloco 10 — Continuidade e recuperação de desastre (2 min)

Seis paradas: cinco em [`dr-plan.md`](dr-plan.md) e uma no `activate-dr.sh`.

> **Abertura** (sem nada específico na tela ainda): "O pedido da diretoria era:
> mesmo que a nuvem falhe, as doações não podem parar. Falha de região inteira é o
> pior caso, e é o que esse plano cobre.
>
> Rodar isso ao vivo levaria 25 minutos, então eu vou mostrar o ensaio que eu
> executei de verdade, com dados reais."

---

**① `dr-plan.md`, linha 10** — o título da seção
`## Estratégia: Warm Standby via Terraform modularizado (Opção B do edital)`

> "Eu escolhi a opção B do edital: contingência morna, com os mesmos módulos
> Terraform na outra região.
>
> Mas repara no detalhe: esse ambiente **não existe** no dia a dia. Ele é criado na
> hora. É a decisão de custo do bloco anterior — deixar tudo parado esperando um
> desastre custaria 145 dólares por mês."

---

**② Role até a tabela, linhas 21–26** — as quatro linhas de "Dado / Estratégia / RPO"

> "E essa tabela é a parte que costuma faltar nos planos: **cada tipo de dado tem
> uma estratégia diferente**.
>
> O banco vai por cópia tirada no momento da ativação, e não uma cópia velha de
> ontem. O DynamoDB já é replicado continuamente, então perda praticamente zero. As
> imagens já estão do outro lado antes de qualquer desastre.
>
> E a fila é recriada vazia — essa perda eu aceito e declaro: perde-se notificação
> em trânsito, não doação. Porque a doação é gravada no banco **antes** de a
> mensagem sair."

---

**③ Seções `## RPO` (linha 28) e `## RTO` (linha 54)** — mostre os dois títulos

> "Os dois números que definem qualquer plano de continuidade: quanto de dado eu
> aceito perder, e quanto tempo eu aceito ficar fora. Aqui: até uma hora de dado, e
> até uma hora fora."

---

**④ Troque para `scripts/activate-dr.sh`, linhas 2–6** — o cabeçalho com as etapas

> "E o plano é executável, não é documento de gaveta. É **um comando**.
>
> Ele tira a cópia do banco, manda pra outra região, cria a infraestrutura e sobe
> as aplicações.
>
> Quem estiver de plantão às 3 da manhã não precisa lembrar de quatro
> procedimentos. Precisa rodar um script."

---

**⑤ Volte ao `dr-plan.md`, seção `## Resultado do ensaio` (linha 171)** — aponte
os dois itens:

- **linhas 182–187**: o RTO medido
- **linhas 188–190**: a prova de RPO

> "E aqui o que separa plano escrito de plano testado.
>
> Eu subi o ambiente, criei uma ONG e duas doações de verdade, simulei a perda da
> região, rodei o script e cronometrei.
>
> **24 minutos e 23 segundos**, contra uma meta de uma hora. A parte lenta é criar
> o cluster, uns 15 a 20 minutos — não tem como acelerar isso sem pagar por
> ambiente parado.
>
> E a prova que interessa, essa linha aqui: eu consultei as doações na região de
> contingência e as duas voltaram inteiras. Mesmo id, mesmo valor, mesma data.
> Nenhum dado transacional perdido."

---

**⑥ Seção `## Limitações conhecidas` (linha 144)** — o primeiro item

> "E uma limitação que eu declaro em vez de esconder: o script lê uma informação
> que fica guardada na região principal. Numa falha total dela, isso seria um ponto
> cego. Por isso existe uma variável de ambiente que pula essa leitura."

---

> **Frase de fechamento**: "As duas doações criadas na região principal aparecem na
> de contingência com o mesmo id e a mesma data. Nada foi perdido."

## Bloco 11 — Encerramento (40 s)

**Na tela**: `terraform destroy` iniciando.

> ⚠️ **Não diga "zero recursos órfãos".** É a frase natural nesse momento e ela
> não é verdadeira. O `terraform destroy` remove tudo que **ele** criou, mas os
> discos EBS dos PVCs do Prometheus e do Loki são criados pelo driver CSI dentro
> do cluster, não pelo Terraform. Ficam para trás, e como não herdam as tags do
> projeto, a consulta `resourcegroupstaggingapi` também não os enxerga — foi
> assim que dois discos por ciclo passaram despercebidos.
>
> Se a banca perguntar sobre limpeza, a resposta forte é a de baixo. Conhecer o
> próprio ponto cego vale mais que uma afirmação absoluta que não se sustenta.

> **Falar, se perguntarem sobre limpeza**: "A infraestrutura que o Terraform
> gerencia some inteira com um comando. Mas tem um detalhe que eu descobri
> conferindo o console: os discos que o Kubernetes cria sozinho, para o
> Prometheus e o Loki, não são do Terraform. Eles ficam para trás.
>
> E o pior é que eles não herdam as etiquetas do projeto, então a consulta por
> etiqueta, que eu usava para conferir sobras, não achava eles. Eu estava
> conferindo com um método cego.
>
> Hoje o procedimento é apagar os volumes antes de destruir o ambiente, e a
> conferência inclui listar disco solto, não só consultar por etiqueta. Está no
> runbook."

> **Falar**: "Eu encerro derrubando tudo. E isso faz parte da demonstração.
>
> Tudo que vocês viram custa mais ou menos **24 centavos de dólar por hora**
> enquanto está de pé. E some inteiro com um comando. É isso que torna a
> contingência sob demanda possível, e a conta pagável por uma ONG.
>
> Recapitulando: três serviços em contêiner rodando no Kubernetes; infraestrutura
> inteira em Terraform, nada pelo console; esteira com análise de segurança e
> bloqueio real por vulnerabilidade; entrega contínua por GitOps com autocorreção;
> monitoramento com métrica, log e rastro; metas de disponibilidade, orçamento de
> erro e um incidente cronometrado até o post-mortem; controle de custo com
> etiquetas, previsão e dimensionamento; e um plano de continuidade **ensaiado**,
> com os tempos medidos.
>
> Duas pendências, que eu prefiro declarar. O envio automático de alerta por
> e-mail no New Relic é bloqueado no plano gratuito — o código está pronto, falta
> o plano. E três ações corretivas do post-mortem seguem abertas, incluindo aquela
> falha de detecção que o próprio ensaio revelou.
>
> Achei mais honesto entregar o problema documentado do que fingir que ele não
> existe.
>
> Todo o código, os documentos e as evidências estão no repositório. Obrigado."

---

## Dicas de gravação

- **Terminal grande** (fonte ≥ 16pt). Comando ilegível não é evidência.
- `clear` antes de cada bloco de terminal.
- Ao abrir um arquivo, aponte **as 2 ou 3 linhas que importam**. Não leia o
  arquivo inteiro.
- Quando algo demorar (sync, alerta), **continue falando** em vez de ficar em
  silêncio. Explique o que está acontecendo enquanto acontece.
- Se algo falhar ao vivo, **não corte**. Diagnosticar em tempo real é exatamente
  a competência que está sendo avaliada.
- **Fale mais devagar do que parece natural.** Na gravação sempre soa mais rápido
  do que na hora.
- Os port-forwards caem quando o pod é recriado. No bloco 7 o `ngo-service` **é**
  recriado, então o túnel da 8081 vai cair. É esperado.

## Se o tempo apertar

Os blocos 6 e 7 são os mais densos. Cada `> Falar` tem o essencial no primeiro
parágrafo e aprofundamento nos seguintes — corte os de baixo e mantenha o
primeiro. Os cortes mais baratos, em ordem:

1. Bloco 3.3 (OIDC) — 15 segundos, dá pra só apontar no YAML.
2. Bloco 8, o achado de pods por máquina.
3. Bloco 6.5 (logs) — o Loki já apareceu no diagrama.

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
