variable "whoami_image" {
  type        = string
  description = "Whoami image to docker-run. Untagged references get `:` + whoami_version appended (e.g. `traefik/whoami` + `v1.11.0`)."
  default     = "ghcr.io/zalbiraw/whoami:latest"
}

variable "whoami_version" {
  type        = string
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  default     = "v1.11.0"
}

variable "arch" {
  type        = string
  description = "The architecture (amd64, arm64)"
  default     = "amd64"
}

variable "port" {
  type        = number
  description = "Host port whoami is published on (docker -p <port>:80)"
  default     = 80
}

# Sets WHOAMI_NAME env var → whoami responds with `Name: <name>` so the audience
# can tell which VM served them. Empty = whoami falls back to the container
# hostname in the response body.
variable "name" {
  type        = string
  description = "Identifier surfaced as `Name:` in the whoami response"
  default     = ""
}

variable "environment" {
  type        = map(string)
  description = "Extra environment variables for the container (docker -e), e.g. OTEL_* exporter config for the OTel-instrumented whoami fork."
  default     = {}
}
