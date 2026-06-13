variable "name" {
  description = "Name of the k6 TestRun + its script ConfigMap."
  type        = string
  default     = "unified-ingress-traffic"
}

variable "namespace" {
  description = "Namespace for the TestRun + ConfigMap (the k6 operator must watch it)."
  type        = string
}

variable "domain" {
  description = "Base demo domain (e.g. unified.demo.traefik.ai). The scenario derives every route host from it."
  type        = string
}

variable "keycloak_url" {
  description = "Keycloak token endpoint (…/realms/<realm>/protocol/openid-connect/token). setup() mints one JWT per user via the password grant."
  type        = string
}

variable "keycloak_client_id" {
  description = "Keycloak client id used for the password grant."
  type        = string
  default     = "traefik"
}

variable "keycloak_client_secret" {
  description = "Keycloak client secret for the password grant."
  type        = string
  sensitive   = true
}

variable "users" {
  description = "Consumer users the scenario authenticates as. Each request to the managed API picks one at random, so its group claim (app_id) shows up per-consumer in the dashboards."
  type = list(object({
    username = string
    password = string
  }))
}

variable "vus" {
  description = "Concurrent virtual users (controls aggregate request rate)."
  type        = number
  default     = 20
}

variable "duration" {
  description = "How long the test runs (k6 duration string, e.g. 2h)."
  type        = string
  default     = "2h"
}

variable "parallelism" {
  description = "k6 TestRun parallelism (number of runner pods the load is split across)."
  type        = number
  default     = 1
}

variable "ai_enabled" {
  description = "Run the AI-gateway traffic scenario (rotates the openai/anthropic model lists). OFF by default: these are billed per call. Kept low-rate (ai_rpm) + small (ai_max_tokens), and the gateway's Redis budget self-caps spend."
  type        = bool
  default     = false
}

variable "openai_models" {
  description = "OpenAI models the AI scenario rotates through (sent to /v1/responses; the gateway allows model override). Cost-managed: keep to cheap chat models."
  type        = list(string)
  default     = ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-4o-2024-08-06"]
}

variable "anthropic_models" {
  description = "Anthropic models the AI scenario rotates through (sent to /v1/messages). Needs the gateway to inject the platform key (enable_messages_api_passthrough_auth = false)."
  type        = list(string)
  default     = ["claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-8", "claude-3-5-haiku-latest", "claude-3-5-sonnet-latest"]
}

variable "ai_rpm" {
  description = "AI requests per MINUTE across all models/providers (constant arrival rate). Low by default for cost control — the dashboard inflates the displayed token/spend numbers separately."
  type        = number
  default     = 6
}

variable "ai_max_tokens" {
  description = "Max output tokens per AI call. Small by default to cap real spend."
  type        = number
  default     = 32
}
