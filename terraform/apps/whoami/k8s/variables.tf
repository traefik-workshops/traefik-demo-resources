variable "apps" {
  description = "Map of applications to deploy to Kubernetes. Each app can have multiple replicas."
  default     = {}
  type = map(object({
    replicas     = optional(number, 1)
    port         = optional(number, 80)
    name         = optional(string)          # whoami `-name` (WHOAMI_NAME) — body shows `Name: <name>`; defaults to the app key
    docker_image = optional(string)          # per-app image override; null = module-level whoami_image
    environment  = optional(map(string), {}) # merged over module-level `environment` into the container
    labels       = optional(map(string), {})
    ingress_route = optional(object({
      enabled     = optional(bool, false)
      host        = optional(string)
      entrypoints = optional(list(string), ["web"])
      middlewares = optional(list(object({
        name      = string
        namespace = optional(string)
      })), [])
      strip_prefix = optional(object({
        enabled  = optional(bool, false)
        prefixes = optional(list(string), [])
      }), {})
    }), {})
  }))
}

variable "uplink_enabled" {
  description = "Advertise the route over a Traefik Hub multicluster uplink instead of serving it locally. When true the IngressRoute drops entryPoints and matches PathPrefix(`/`) (Hub attaches it to the uplink), so ingress_route.host and ingress_route.strip_prefix are IGNORED for matching — the parent cluster owns the Host match. Supports at most one app with ingress_route.enabled (one Uplink is shared). Requires uplink_name."
  type        = bool
  default     = false
}

variable "uplink_name" {
  description = "Uplink name to advertise on. Required when uplink_enabled. Must match the child's --hub.uplinkEntryPoints.<name> entrypoint and the parent's <name>@multicluster service ref."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Kubernetes namespace to deploy applications"
  type        = string
  default     = "apps"
}

variable "whoami_image" {
  description = "Whoami image for every app that doesn't set its own docker_image."
  type        = string
  default     = "ghcr.io/traefik-workshops/whoami:latest"
}

variable "environment" {
  description = "Environment variables added to every whoami container, e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node selector for pod scheduling"
  type        = map(string)
  default     = {}
}

variable "ingress_observability" {
  type        = bool
  description = "Emit Traefik observability signals (access logs, metrics, traces) for every whoami IngressRoute this module creates. Set to false to add the three `traefik.ingress.kubernetes.io/router.observability.*: \"false\"` annotations. Same switch shape as other k8s modules."
  default     = true
}

variable "ingress_annotations" {
  type        = map(string)
  description = "Additional metadata annotations merged onto every whoami IngressRoute. Useful for custom router options beyond the three observability toggles."
  default     = {}
}
