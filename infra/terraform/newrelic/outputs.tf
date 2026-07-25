output "donation_service_policy_id" {
  description = "ID da alert policy do Hot Path (usado pelo Workflow e para conferir na UI)."
  value       = newrelic_alert_policy.donation_service.id
}

output "platform_policy_id" {
  description = "ID da alert policy de plataforma (Kubernetes)."
  value       = newrelic_alert_policy.platform.id
}

output "workflow_id" {
  description = "ID do Workflow que notifica o e-mail de plantão."
  value       = newrelic_workflow.donation_service.id
}

output "condition_ids" {
  description = "IDs compostos (<policy_id>:<condition_id>) das condições criadas."
  value = {
    error_rate         = newrelic_nrql_alert_condition.donation_error_rate.id
    latency_p95        = newrelic_nrql_alert_condition.donation_latency_p95.id
    throughput_anomaly = newrelic_nrql_alert_condition.donation_throughput_anomaly.id
    latency_anomaly    = newrelic_nrql_alert_condition.donation_latency_anomaly.id
    pod_restarts       = newrelic_nrql_alert_condition.pod_restarts.id
  }
}
