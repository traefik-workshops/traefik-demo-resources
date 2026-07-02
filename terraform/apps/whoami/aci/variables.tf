variable "apps" {
  description = "Map of applications to deploy to ACI. Each app can have multiple replicas (one container group each). Same shape as apps/whoami/ec2: { name = { replicas, port, name, tags } }."
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

variable "whoami_version" {
  description = "The traefik/whoami image tag to run — they carry a `v` prefix (e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
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
