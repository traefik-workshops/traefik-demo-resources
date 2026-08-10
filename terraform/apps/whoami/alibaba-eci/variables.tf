variable "apps" {
  description = "Map of applications to deploy to ECI. Each app can have multiple replicas (one container group each). Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` become dotted-key traefik.* container-group tags."
  type        = any
  default     = {}
}

variable "vswitch_id" {
  description = "ID of the existing vswitch the container groups join (e.g. compute/alibaba/vpc's vswitch_id, so the Traefik child reaches them in-VPC)"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID attached to the container groups (required by ECI, e.g. compute/alibaba/vpc's security_group_id)"
  type        = string
}

variable "container_cpu" {
  description = "vCPUs per container group (0.25 is ECI's minimum)"
  type        = number
  default     = 0.25
}

variable "container_memory" {
  description = "Memory (GB) per container group (0.5 is ECI's minimum for 0.25 vCPU)"
  type        = number
  default     = 0.5
}

variable "common_tags" {
  description = "Common tags to apply to all container groups"
  type        = map(string)
  default     = {}
}

variable "whoami_image" {
  description = "Whoami image every container group runs. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "ghcr.io/traefik-workshops/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables added to every whoami container, e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}
