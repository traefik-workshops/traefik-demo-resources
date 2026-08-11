variable "clusters" {
  description = "Map of ECS clusters with their echo applications. Each app may set an optional `environment` (map) merged over the module-level `environment` into the task's container definition."
  type        = any
  default     = {}
}

variable "whoami_image" {
  description = "Whoami image every task runs."
  type        = string
  default     = "ghcr.io/traefik-workshops/whoami:latest"
}

variable "environment" {
  description = "Environment variables added to every whoami container definition, e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "Name of the ECS Deployment"
  type        = string
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "create_vpc" {
  description = "Create VPC if vpc_id is not provided"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID for ECS resources"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS resources"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for ECS resources"
  type        = list(string)
  default     = []
}

variable "otlp_gate_address" {
  description = "OTLP collector base URL (e.g. https://collector.example.com). When set, a sidecar blocks each whoami task from starting until that endpoint accepts an OTLP write. Set it whenever the tasks export telemetry: the whoami fork's exporter has no recovery path, so a task that starts against a collector that is not up yet — or against a stale DNS record still pointing at a destroyed load balancer — serves traffic perfectly and reports nothing. Empty disables the gate."
  type        = string
  default     = ""
}
