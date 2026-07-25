# Camada de AIOps/ITSM no New Relic, como código (Fase 7).
#
# Por que um root module separado de envs/primary: o ciclo de vida é
# diferente. A infra AWS é efêmera (`terraform destroy` depois de cada
# demo — ver docs/finops-forecast.md), mas as políticas de alerta, o
# destination de e-mail e o Workflow são configuração de conta SaaS que
# faz sentido manter de pé entre os ciclos (custo zero no free tier). Se
# ficassem em envs/primary, cada destroy apagaria o Workflow e a próxima
# demo começaria sem alerta configurado.
#
# Pré-requisitos (ver docs/itsm-incident-flow.md):
#   export NEW_RELIC_ACCOUNT_ID=...        # Administration -> Access management
#   export NEW_RELIC_API_KEY=NRAK-...      # User key (NÃO é a license key dos apps)
#   export NEW_RELIC_REGION=US
#   terraform init -backend-config=backend.hcl
#   terraform apply -var 'alert_emails=["voce@exemplo.com"]'
#
# Os dados consultados pelas NRQL abaixo chegam de duas fontes já
# implementadas na Fase 5:
#   - `Span`: OTLP direto dos 3 serviços (apps/donation-service/tracing.go e
#     a auto-instrumentação dos serviços Python), habilitado quando
#     NEW_RELIC_LICENSE_KEY está definida no scripts/deploy-primary.sh.
#   - `K8sContainerSample`: nri-bundle (gitops/apps/base/nri-bundle-app.yaml).

locals {
  # span.kind = 'server' descarta os spans de cliente (a chamada
  # donation -> ngo aparece como client no donation-service); o filtro de
  # método POST isola POST /donations dos GETs de /health, /ready e
  # /metrics, que são ruído de infraestrutura e não tráfego de doação
  # (mesmo recorte usado nos SLIs Prometheus — ver docs/sre-slo.md).
  # As duas grafias de método cobrem as convenções semânticas antiga
  # (http.method) e atual (http.request.method) do OpenTelemetry.
  donation_hot_path_filter = <<-EOT
    service.name = 'donation-service'
    AND span.kind = 'server'
    AND (http.request.method = 'POST' OR http.method = 'POST')
  EOT

  # SLI de disponibilidade: proporção de respostas 5xx, exatamente o
  # recorte do SLI Prometheus (status!~"5..") — os dois sinais precisam
  # concordar, senão o alerta do New Relic e o do Alertmanager contam
  # histórias diferentes sobre o mesmo incidente.
  server_error_filter = "http.response.status_code >= 500 OR http.status_code >= 500"
}

resource "newrelic_alert_policy" "donation_service" {
  name = "SolidaryTech - donation-service (Hot Path)"

  # Um incidente por condição/entidade: um problema de latência não é
  # agrupado com um problema de disponibilidade, o que manteria o issue
  # aberto (e o MTTR contando) depois de um dos dois já ter sido resolvido.
  incident_preference = "PER_CONDITION_AND_TARGET"
}

resource "newrelic_alert_policy" "platform" {
  name                = "SolidaryTech - plataforma (Kubernetes)"
  incident_preference = "PER_CONDITION_AND_TARGET"
}

# --------------------------------------------------------------------------
# Condições estáticas: espelham os SLOs de docs/sre-slo.md
# --------------------------------------------------------------------------

resource "newrelic_nrql_alert_condition" "donation_error_rate" {
  policy_id = newrelic_alert_policy.donation_service.id
  type      = "static"
  name      = "donation-service: taxa de erro em POST /donations"
  description = join(" ", [
    "Espelha o SLI de disponibilidade do SLO 99,9%/30d.",
    "Limiar critico = 14,4x o error budget (queima o budget de 30 dias em ~2 dias);",
    "warning = 6x (queima em ~5 dias). Ver docs/sre-slo.md.",
  ])
  runbook_url = "${var.runbook_base_url}/itsm-incident-flow.md"
  enabled     = true

  violation_time_limit_seconds = 3600
  aggregation_method           = "event_flow"
  aggregation_window           = 60
  aggregation_delay            = 120

  nrql {
    query = "SELECT percentage(count(*), WHERE ${local.server_error_filter}) FROM Span WHERE ${local.donation_hot_path_filter}"
  }

  critical {
    operator              = "above"
    threshold             = var.error_rate_critical_percent
    threshold_duration    = 300
    threshold_occurrences = "all"
  }

  warning {
    operator              = "above"
    threshold             = var.error_rate_warning_percent
    threshold_duration    = 900
    threshold_occurrences = "all"
  }
}

resource "newrelic_nrql_alert_condition" "donation_latency_p95" {
  policy_id   = newrelic_alert_policy.donation_service.id
  type        = "static"
  name        = "donation-service: latencia p95 em POST /donations"
  description = "Espelha o SLO de latencia (p95 < ${var.latency_p95_threshold_ms}ms) de docs/sre-slo.md."
  runbook_url = "${var.runbook_base_url}/itsm-incident-flow.md"
  enabled     = true

  violation_time_limit_seconds = 3600
  aggregation_method           = "event_flow"
  aggregation_window           = 60
  aggregation_delay            = 120

  nrql {
    query = "SELECT percentile(duration.ms, 95) FROM Span WHERE ${local.donation_hot_path_filter}"
  }

  critical {
    operator              = "above"
    threshold             = var.latency_p95_threshold_ms
    threshold_duration    = 300
    threshold_occurrences = "all"
  }
}

# --------------------------------------------------------------------------
# Anomaly detection (AIOps): condições baseline. O limiar não é um número
# fixo — o New Relic aprende o comportamento normal do sinal e alerta em
# desvios-padrão, o que é o que pega o incidente ANTES de o SLO ser
# violado (requisito "resposta preditiva, não apenas reativa" do edital).
# --------------------------------------------------------------------------

resource "newrelic_nrql_alert_condition" "donation_throughput_anomaly" {
  policy_id = newrelic_alert_policy.donation_service.id
  type      = "baseline"
  name      = "donation-service: anomalia de throughput (baseline)"
  description = join(" ", [
    "Deteccao de anomalia: desvio do throughput normal de doacoes em",
    "qualquer direcao. upper_and_lower porque os dois lados sao incidente:",
    "queda = doacoes deixaram de chegar (o pior cenario para a ONG, e",
    "invisivel para um alerta de taxa de erro); alta = pico de acesso que",
    "pode saturar o Hot Path antes de o HPA reagir.",
  ])
  runbook_url = "${var.runbook_base_url}/itsm-incident-flow.md"
  enabled     = true

  baseline_direction = "upper_and_lower"
  signal_seasonality = "NEW_RELIC_CALCULATION"

  violation_time_limit_seconds = 3600
  aggregation_method           = "event_flow"
  aggregation_window           = 60
  aggregation_delay            = 120

  nrql {
    query = "SELECT rate(count(*), 1 minute) FROM Span WHERE ${local.donation_hot_path_filter}"
  }

  # Em condição baseline, `threshold` é número de desvios-padrão, não valor
  # absoluto (e `operator` só aceita "above").
  critical {
    operator              = "above"
    threshold             = 4
    threshold_duration    = 300
    threshold_occurrences = "all"
  }

  warning {
    operator              = "above"
    threshold             = 2
    threshold_duration    = 600
    threshold_occurrences = "all"
  }
}

resource "newrelic_nrql_alert_condition" "donation_latency_anomaly" {
  policy_id = newrelic_alert_policy.donation_service.id
  type      = "baseline"
  name      = "donation-service: anomalia de latencia (baseline)"
  description = join(" ", [
    "Complementa a condicao estatica de p95: dispara quando a latencia",
    "foge do padrao aprendido mesmo sem ter cruzado os 300ms do SLO —",
    "e o sinal que permite agir dentro do error budget, nao depois.",
  ])
  runbook_url = "${var.runbook_base_url}/sre-slo.md"
  enabled     = true

  baseline_direction = "upper_only"
  signal_seasonality = "NEW_RELIC_CALCULATION"

  violation_time_limit_seconds = 3600
  aggregation_method           = "event_flow"
  aggregation_window           = 60
  aggregation_delay            = 120

  nrql {
    query = "SELECT average(duration.ms) FROM Span WHERE ${local.donation_hot_path_filter}"
  }

  critical {
    operator              = "above"
    threshold             = 3
    threshold_duration    = 300
    threshold_occurrences = "all"
  }
}

# --------------------------------------------------------------------------
# Plataforma: sinais de infraestrutura vindos do nri-bundle
# --------------------------------------------------------------------------

resource "newrelic_nrql_alert_condition" "pod_restarts" {
  policy_id   = newrelic_alert_policy.platform.id
  type        = "static"
  name        = "solidarytech: containers reiniciando (CrashLoop)"
  description = "Equivalente New Relic do alerta SolidaryTechPodCrashLooping do Prometheus (gitops/platform/prometheusrules/)."
  runbook_url = "${var.runbook_base_url}/itsm-incident-flow.md"
  enabled     = true

  violation_time_limit_seconds = 3600
  aggregation_method           = "event_flow"
  aggregation_window           = 300
  aggregation_delay            = 120

  nrql {
    query = "SELECT max(restartCount) - min(restartCount) FROM K8sContainerSample WHERE clusterName = '${var.cluster_name}' AND namespaceName = '${var.namespace}' FACET podName"
  }

  critical {
    operator              = "above"
    threshold             = 2
    threshold_duration    = 300
    threshold_occurrences = "at_least_once"
  }
}

# --------------------------------------------------------------------------
# Notificação: destination de e-mail + channel + Workflow
# (fluxo "Deteccao -> Alerta" de docs/itsm-incident-flow.md)
# --------------------------------------------------------------------------

resource "newrelic_notification_destination" "email" {
  name = "SolidaryTech - plantao (e-mail)"
  type = "EMAIL"

  property {
    key   = "email"
    value = join(",", var.alert_emails)
  }
}

resource "newrelic_notification_channel" "email" {
  name           = "SolidaryTech - plantao (e-mail)"
  type           = "EMAIL"
  destination_id = newrelic_notification_destination.email.id

  # "IINT" (incident intelligence) é obrigatório para o channel poder ser
  # usado por um Workflow.
  product = "IINT"

  property {
    key   = "subject"
    value = "[SolidaryTech] {{ annotations.title.[0] }}"
  }

  property {
    key   = "customDetailsEmail"
    value = <<-EOT
      Issue: {{ issuePageUrl }}
      Prioridade: {{ priority }}
      Politica: {{#each accumulations.policyName}}{{this}} {{/each}}
      Condicao: {{#each accumulations.conditionName}}{{this}} {{/each}}
      Runbook: {{#each accumulations.runbookUrl}}{{this}} {{/each}}
      Descricao: {{#each annotations.description}}{{this}} {{/each}}
    EOT
  }
}

resource "newrelic_workflow" "donation_service" {
  name = "SolidaryTech - incidentes do Hot Path"

  # Sem regras de muting neste projeto: todo issue notifica.
  muting_rules_handling = "NOTIFY_ALL_ISSUES"

  # Enrichment é o "contexto automático" do AIOps: a notificação já chega
  # com o número de erros da última meia hora, sem ninguém precisar abrir
  # a UI para descobrir o tamanho do problema.
  enrichments {
    nrql {
      name = "Erros 5xx (30 min)"
      configuration {
        query = "SELECT count(*) FROM Span WHERE ${local.donation_hot_path_filter} AND (${local.server_error_filter}) SINCE 30 minutes ago"
      }
    }
  }

  issues_filter {
    name = "Politicas SolidaryTech"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values = [
        newrelic_alert_policy.donation_service.id,
        newrelic_alert_policy.platform.id,
      ]
    }
  }

  destination {
    channel_id = newrelic_notification_channel.email.id

    # ACTIVATED e CLOSED: os dois eventos que delimitam o MTTR — a
    # diferença entre os dois e-mails é o tempo de recuperação registrado
    # no post-mortem (docs/postmortem-template.md).
    notification_triggers = ["ACTIVATED", "ACKNOWLEDGED", "CLOSED"]
  }
}
