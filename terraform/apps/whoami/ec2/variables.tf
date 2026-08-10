variable "apps" {
  description = "Map of applications to deploy to EC2. Each app can have multiple replicas. { name = { replicas, port, name, environment, tags, instance_name, ... } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` land on the instance (how `traefik.*` discovery tags get set); `instance_name` gives every replica of the app one shared `Name` tag instead of the default per-instance `<app>-<replica>`."
  type        = any
  default     = {}
}

variable "instance_type" {
  description = "EC2 instance type for all echo servers"
  type        = string
  default     = "t3.micro"
}

variable "common_tags" {
  description = "Common tags to apply to all instances"
  type        = map(string)
  default     = {}
}

variable "create_vpc" {
  description = "Create VPC if vpc_id is not provided"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
  default     = []
}

variable "whoami_image" {
  description = "Whoami image to docker-run on each instance. Untagged references get `:` + whoami_version appended."
  type        = string
  # ghcr, not docker.io: container platforms' anonymous Docker Hub pulls get
  # rate-limited (ACI hit three straight 409s on first deploy, 2026-07).
  default = "ghcr.io/traefik-workshops/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables passed to every whoami container (docker -e), e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}

variable "ami_architecture" {
  description = "The architecture (x86_64, arm64)"
  type        = string
  default     = "x86_64"
}
