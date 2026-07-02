variable "apps" {
  description = "Map of applications to deploy as Code Engine apps: { name = { port, name, environment } }. Optional `environment` (map) is merged over the module-level `environment` into the container. NO traefik config surface exists (labels/annotations are not user-settable on Code Engine) — the Hub ibmCodeEngine provider routes every ready app by its defaultRule."
  type        = any
  default     = {}
}

variable "project_name" {
  description = "Name of the Code Engine project the module creates (when enable_project = true)"
  type        = string
  default     = "whoami"
}

variable "enable_project" {
  description = "Create the Code Engine project in this module. Disable to deploy into an existing project via project_id."
  type        = bool
  default     = true
}

variable "project_id" {
  description = "Existing Code Engine project ID (GUID) to deploy into. Required when enable_project = false."
  type        = string
  default     = ""
}

variable "resource_group_id" {
  description = "Resource group ID the module-created project lands in. Empty = the account's default resource group."
  type        = string
  default     = ""
}

variable "managed_domain_mappings" {
  description = "Endpoint visibility of the apps: local_public (public + project-local), local_private (private network + project-local), or local (project-local only). The ibmCodeEngine provider surfaces it as the `visibility` pseudo-label for constraints."
  type        = string
  default     = "local_public"
}

variable "min_scale" {
  description = "Minimum instances per app. Keep >= 1 so the ibmCodeEngine provider (which only routes READY apps) always sees a ready instance."
  type        = number
  default     = 1
}

variable "max_scale" {
  description = "Maximum instances per app"
  type        = number
  default     = 1
}

variable "whoami_image" {
  description = "Whoami image to run (Code Engine pulls public Docker Hub images directly). Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "docker.io/zalbiraw/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables passed to every whoami container, e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}
