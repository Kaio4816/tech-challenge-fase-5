variable "cluster_name" {
  description = "Nome do cluster EKS reportado pelo nri-bundle (global.cluster em gitops/apps/base/nri-bundle-app.yaml)."
  type        = string
  default     = "solidarytech-primary-eks"
}

variable "namespace" {
  description = "Namespace Kubernetes dos 3 serviços (usado nas condições de infraestrutura)."
  type        = string
  default     = "solidarytech"
}

variable "alert_emails" {
  description = "E-mails que recebem as notificações do Workflow (destination EMAIL). Lista separada por vírgula é montada automaticamente."
  type        = list(string)
}

variable "runbook_base_url" {
  description = "Base para os links de runbook exibidos nas notificações."
  type        = string
  default     = "https://github.com/Kaio4816/tech-challenge-fase-5/blob/main/docs"
}

variable "latency_p95_threshold_ms" {
  description = "Limiar de latência p95 de POST /donations, em ms (deve casar com o SLO de docs/sre-slo.md)."
  type        = number
  default     = 300
}

variable "error_rate_critical_percent" {
  description = "Limiar crítico da taxa de erro de POST /donations, em % (14.4x o budget de 0,1% do SLO 99,9% — ver docs/sre-slo.md)."
  type        = number
  default     = 1.44
}

variable "error_rate_warning_percent" {
  description = "Limiar de warning da taxa de erro de POST /donations, em % (6x o budget de 0,1%)."
  type        = number
  default     = 0.6
}
