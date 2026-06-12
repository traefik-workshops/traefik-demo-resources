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
  description = "Include a small slice of real AI-gateway calls (gpt-4o-mini / claude-haiku-4-5). OFF by default: these are billed per call (the gateway's Redis budget self-caps spend)."
  type        = bool
  default     = false
}
