variable "whoami_version" {
  type        = string
  description = "The Whoami version to install"
  default     = "v1.11.0"
}

variable "arch" {
  type        = string
  description = "The architecture (amd64, arm64)"
  default     = "amd64"
}

variable "port" {
  type        = number
  description = "Port for whoami to listen on"
  default     = 80
}

# Sets WHOAMI_NAME env var → whoami responds with `Name: <name>` so the audience
# can tell which VM served them. Empty = whoami falls back to OS hostname (which
# isn't set by this cloud-init, so the response would just show "ubuntu").
variable "name" {
  type        = string
  description = "Identifier surfaced as `Name:` in the whoami response"
  default     = ""
}
