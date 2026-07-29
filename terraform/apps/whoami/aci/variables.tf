variable "apps" {
  description = "Map of applications to deploy to ACI. Each app can have multiple replicas (one container group each). Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container."
  type        = any
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group the container groups are created in"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
  default     = "eastus"
}

variable "common_tags" {
  description = "Common tags to apply to all container groups"
  type        = map(string)
  default     = {}
}

variable "create_vnet" {
  description = "Create a demo VNet (compute/azure/vnet) if subnet_id is not provided. Off by default — these container groups normally join an existing delegated subnet."
  type        = bool
  default     = false
}

variable "subnet_id" {
  description = "ID of the existing subnet the container groups join. MUST be delegated to Microsoft.ContainerInstance (compute/azure/vnet's aci_subnet_id already is)."
  type        = string
  default     = ""

  validation {
    condition     = var.create_vnet || var.subnet_id != ""
    error_message = "subnet_id must be provided if create_vnet is false"
  }
}

variable "whoami_image" {
  description = "Whoami image every container group runs. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "ghcr.io/zalbiraw/whoami:latest"
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

variable "container_cpu" {
  description = "vCPU allocation per whoami container"
  type        = string
  default     = "0.5"
}

variable "container_memory" {
  description = "Memory allocation (GB) per whoami container"
  type        = string
  default     = "1.0"
}
