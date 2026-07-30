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

> **Falar** (abrindo o job do Trivy no YAML): "Esse job aqui é um portão. Três
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

### 3.3 — Sem senha guardada

> **Falar** (abrindo o job de push): "Um detalhe de segurança. Para enviar a
> imagem pra AWS não existe chave de acesso nenhuma guardada no GitHub. A
> autenticação é por OIDC: o GitHub prova quem ele é, e a AWS entrega um crachá
> temporário. Não tem senha para vazar."

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

Abrir <https://github.com/Kaio4816/tech-challenge-fase-5/commit/c0149ca>.

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
> detecção leva uns 6 a 7 minutos e você volta nele no bloco 7.
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

Volte ao terminal do ensaio disparado no bloco 6.

> **Falar**: "Tudo que eu mostrei está de pé e saudável. Agora eu quebro de
> propósito, com cronômetro.
>
> O incidente é realista: eu derrubo o `ngo-service`, que é a dependência do
> caminho crítico. Aquela seta do começo do vídeo."

> ✅ **O drill valida a própria medição.** Se a linha de base do p95 já estiver
> acima dos 300 ms do SLO, ele **aborta** com instrução de reduzir a concorrência,
> em vez de seguir e produzir um número que parece válido e não é. Ou seja: se o
> ensaio chegou até o fim, a medição é confiável. Isso vale citar em uma frase.

**Narrar conforme os marcos aparecem.** Leia os números da sua tela — os valores
entre parênteses são as faixas medidas em rodadas anteriores, para você saber o
que esperar, não para decorar.

| Momento | O que dizer |
|---|---|
| `BASELINE_P95_MS` (~20 ms) | "Antes de quebrar nada, o script mediu a linha de base: cerca de 20 milissegundos. Bem abaixo do meu limite de 300. É a partir daqui que a comparação vale." |
| `T0_INICIO_IMPACTO` | "Aqui começa o incidente. Derrubei a dependência para zero réplicas." |
| `FALHA_EFETIVA` (+5s) | "Confirmado: zero réplicas prontas. A dependência sumiu de verdade." |
| `DEGRADACAO_P95` (~1000 ms) | "E a latência salta de 20 milissegundos para cerca de 1 segundo. É o Hot Path esperando o timeout da dependência." |
| — | "Mas olha o que importa: **nenhuma doação falhou**. Continua gravando normalmente, com a dependência fora." |
| `ALERTA_FIRING` (~+6 a 7 min) | "Uns 400 segundos até o alerta disparar. Esse é o tempo de detecção." |
| `LIBERACAO` | "Agora eu solto o incidente e paro de segurar. Daqui pra frente é o ArgoCD." |
| `T3_RECUPERADO` | "E recuperou, sem eu digitar nada. O ArgoCD viu que o cluster estava diferente do Git e restaurou." |

> ⚠️ **O tempo de recuperação varia entre rodadas** — já medi 37 segundos e já
> medi 3 minutos e 16, dependendo de quanto o agendador demora a colocar o pod
> num nó. Não prometa um número antes de ler a tela. O que é constante é que
> **ninguém intervém**.

### Os pontos que valem nota

> **Falar (1) — o fail-open**: "Repara no que **não** aconteceu. Nenhum alerta de
> erro. Nenhuma doação perdida.
>
> Porque a validação é o que se chama fail-open: se o outro serviço cai, a doação
> é gravada mesmo assim. Só um 'ONG não existe' explícito rejeita.
>
> Então a queda da dependência virou **lentidão, não erro**. E como o orçamento
> de erro está ligado a falha, ele saiu **intacto** do incidente.
>
> Consequência prática: quem for investigar isso procurando erro procura no lugar
> errado. Está escrito no runbook por causa disso."

> **Falar (2) — a recuperação automática**: "A recuperação não teve mão humana. Eu
> soltei o incidente e o ArgoCD restaurou. *(diga o tempo que apareceu na tela)*
>
> Isso é o self-heal: o estado desejado está no Git, o cluster divergiu, e ele
> desfez a divergência sozinho."

> **Falar (3) — detectar é mais lento que corrigir**: "E aqui o achado mais
> interessante, que é meio desconfortável.
>
> Detectar levou uns 400 segundos. Recuperar levou muito menos. A recuperação é
> várias vezes mais rápida que a detecção.
>
> Ou seja: sem eu segurar o incidente de propósito, o sistema **se cura antes de
> perceber que está doente**. É ótimo pro usuário e péssimo pra quem opera, porque
> falha que não deixa rastro é falha que se repete.
>
> Eu não descobri isso no papel, descobri rodando. E virou ação corretiva no
> post-mortem, com dono."

> **Falar (4) — a medição que se valida**: "Uma coisa que eu acrescentei depois de
> um ensaio dar errado: antes de quebrar qualquer coisa, o script mede a linha de
> base e **compara com o SLO**. Se a linha de base já estiver acima do limiar, ele
> aborta.
>
> Porque numa rodada anterior a minha própria carga de teste estava saturando o
> banco. A latência já estava em 352 milissegundos antes da falha, e durante a
> falha ficou em 351. O alerta disparou, mas não estava medindo o incidente —
> estava medindo o gerador de carga.
>
> O número parecia perfeitamente válido. Medição que não sabe dizer quando está
> inválida é pior que não medir. Então agora o ensaio se recusa a rodar nessa
> condição."

> ⚠️ **Não prometa o que não vai acontecer**: `SolidaryTechTargetDown` **não**
> dispara nesse cenário (com zero réplicas a série `up` desaparece, e ausência não
> satisfaz `== 0`), e **não haverá e-mail do New Relic** — o roteamento automático
> é bloqueado no plano gratuito. Citar como achado é mais forte do que omitir e ser
> perguntado.

> ⚠️ **Pré-requisito da rodada válida**: um único gerador de carga. O drill sobe o
> seu próprio, então mate qualquer carga anterior antes (`pkill -f "hey -z"`) e
> espere o p95 cair. O script verifica isso e recusa rodar se houver outra carga
> ativa — ver a nota no início do bloco 6.
> Se o aviso `BASELINE_INVALIDA` aparecer de novo, baixe mais a concorrência.

> **Frase de fechamento**: "Detectamos em 6 minutos e recuperamos em 3, sem
> ninguém intervir. E o ensaio mostrou o gargalo real: é a detecção, não a
> correção. Mostrou também que a minha carga de teste estava saturando o banco —
> e é melhor descobrir isso num ensaio do que numa apresentação."

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

> **Falar**: "A previsão é linha a linha. Dá **150 dólares por mês** se ficasse
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

> **Falar**: "O incidente que vocês viram não é um evento solto. Ele percorre um
> processo, e cada caixa aqui aponta pra um arquivo que existe no repositório.
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

**Na tela**: `infra/terraform/newrelic/main.tf` e depois as condições no New Relic

> **Falar**: "E aqui a parte de inteligência artificial que o edital pede. Essas
> duas condições são do tipo **baseline**.
>
> Em vez de eu dizer 'alerta acima de 300 milissegundos', o New Relic **aprende**
> como o serviço se comporta normalmente e avisa quando ele foge do padrão.
>
> A diferença é essa: alerta comum só existe depois que já teve erro. O baseline
> dispara quando o comportamento **muda**, mesmo sem erro nenhum. Por exemplo, se
> as doações simplesmente pararem de chegar num horário em que sempre chegam.
> Nenhum alerta de erro pegaria isso, porque não tem erro.
>
> E olha que isso é Terraform, não configuração clicada. Alerta configurado na mão
> é alerta que se perde no próximo ambiente."

> **Frase de fechamento**: "Detecção preditiva é o limiar aprendido, não o limiar
> fixo. Ele dispara quando o comportamento muda, antes de a meta ser violada."

## Bloco 10 — Continuidade e recuperação de desastre (2 min)

> **Falar**: "O pedido da diretoria era: mesmo que a nuvem falhe, as doações não
> podem parar. Falha de região inteira é o pior caso, e é o que esse plano cobre.
>
> Rodar isso ao vivo levaria 25 minutos, então eu vou apresentar o ensaio que eu
> executei de verdade, com dados reais."

**Na tela**: [`dr-plan.md`](dr-plan.md)

> **Falar**: "Eu escolhi a opção B do edital: contingência morna, com os mesmos
> módulos Terraform na outra região.
>
> Mas repara: esse ambiente **não existe** no dia a dia. Ele é criado na hora. É a
> decisão de custo do bloco anterior — deixar tudo parado esperando um desastre
> custaria 145 dólares por mês.
>
> Os dois números que definem qualquer plano de continuidade: quanto de dado eu
> aceito perder, e quanto tempo eu aceito ficar fora. Aqui: até uma hora de dado,
> e até uma hora fora.
>
> E essa tabela é a parte que costuma faltar nos planos: **cada tipo de dado tem
> uma estratégia diferente**.
>
> O banco vai por cópia tirada no momento da ativação, e não uma cópia velha de
> ontem. O DynamoDB já é replicado continuamente, então perda praticamente zero.
> As imagens já estão do outro lado antes de qualquer desastre. E a fila é
> recriada vazia — essa perda eu aceito e declaro: perde-se notificação em
> trânsito, não doação, porque a doação é gravada antes da mensagem sair."

**Na tela**: `scripts/activate-dr.sh`

> **Falar**: "E o plano é executável, não é documento de gaveta. É **um comando**.
> Ele tira a cópia do banco, manda pra outra região, cria a infraestrutura e sobe
> as aplicações.
>
> Quem estiver de plantão às 3 da manhã não precisa lembrar de quatro
> procedimentos. Precisa rodar um script."

**Na tela**: seção "Resultado do ensaio" do `dr-plan.md`

> **Falar**: "E aqui o que separa plano escrito de plano testado.
>
> Eu subi o ambiente, criei uma ONG e duas doações de verdade, simulei a perda da
> região, rodei o script e cronometrei.
>
> **24 minutos e 23 segundos**, contra uma meta de uma hora. A parte lenta é criar
> o cluster, uns 15 a 20 minutos. Não tem como acelerar isso sem pagar por
> ambiente parado.
>
> E a prova que interessa: eu consultei as doações na região de contingência, e as
> duas voltaram inteiras. Mesmo id, mesmo valor, mesma data. Nenhum dado
> transacional perdido.
>
> Uma limitação que eu declaro em vez de esconder: o script lê informação que fica
> guardada na região principal. Numa falha total dela, isso seria um ponto cego.
> Por isso existe uma variável que pula essa leitura."

> **Frase de fechamento**: "As duas doações criadas na região principal aparecem
> na de contingência com o mesmo id e a mesma data. Nada foi perdido."

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
> Tudo que vocês viram custa mais ou menos **20 centavos de dólar por hora**
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
