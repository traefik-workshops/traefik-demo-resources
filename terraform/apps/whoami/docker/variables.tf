variable "apps" {
  type        = any
  description = "Apps to run as Docker containers, keyed by app name. Each value: { replicas, name, environment, traefik_labels }. `name` is the container basename AND the WHOAMI_NAME the body echoes; `traefik_labels` is the discovery config the local docker provider reads."
  default     = {}
}

variable "whoami_image" {
  # ghcr, not Docker Hub: anonymous docker.io pulls are rate-limited hard enough that the
  # ACI leg took three 409s in a row during validation.
  type        = string
  description = "Whoami image to docker-run. A tag in the last path segment wins over whoami_version."
  default     = "ghcr.io/traefik-workshops/whoami:latest"
}

variable "whoami_version" {
  type        = string
  description = "Image tag used ONLY when whoami_image carries none."
  default     = "v1.11.0"
}

variable "environment" {
  type        = map(string)
  description = "Environment variables applied to every container (the OTel block, typically). A per-app `environment` wins on collision."
  default     = {}
}

variable "common_labels" {
  type        = map(string)
  description = "Traefik labels applied to every container, merged under each app's own traefik_labels."
  default     = {}
}
