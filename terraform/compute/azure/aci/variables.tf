# =============================================================================
# compute/azure/aci — shared azurerm_container_group fleet
# =============================================================================
# Owns ONLY the container group resource. Everything role-specific (the Hub
# commands + token, the aci-provider discovery tags, the whoami WHOAMI_* env,
# the file-provider secret volume) is rendered by the CALLER and passed in as
# opaque inputs. Mirrors the split in compute/aws/ec2.
# =============================================================================

variable "container_groups" {
  description = "Map of container groups to create, keyed by the group name (the map key IS azurerm_container_group.name — the traefik caller passes a single entry keyed by its group name, the whoami caller passes one entry per app replica: `<app>-<replica>`). Each entry carries only the per-group config that varies between groups; everything shared (image, cpu, memory, commands, ...) is a module-level input."
  type = map(object({
    ports                 = optional(list(number), []) # container-level exposed ports (one `ports {}` block each)
    environment_variables = optional(map(string), {})  # container env vars (already merged by the caller)
    tags                  = optional(map(string), {})  # per-group tags, merged over common_tags
  }))
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

variable "subnet_id" {
  description = "ID of the existing subnet every container group joins. For a Private ip_address_type it MUST be delegated to Microsoft.ContainerInstance (compute/azure/vnet's aci_subnet_id already is)."
  type        = string
}

variable "os_type" {
  description = "Container group OS type"
  type        = string
  default     = "Linux"
}

variable "restart_policy" {
  description = "Container group restart policy"
  type        = string
  default     = "Always"
}

variable "ip_address_type" {
  description = "Container group IP address type. `Private` gives a vnet-injected IP (the default for these demo spokes); `Public` gives a public IP + FQDN."
  type        = string
  default     = "Private"
}

variable "enable_system_identity" {
  description = "Attach a system-assigned managed identity to every container group (the Traefik child needs one for the aci provider's DefaultAzureCredential; whoami does not)."
  type        = bool
  default     = false
}

variable "container_name" {
  description = "Name of the single container inside each group (e.g. \"traefik\" or \"whoami\")"
  type        = string
}

variable "image" {
  description = "Fully-qualified container image every group runs (already resolved by the caller — this module does no tag inference)"
  type        = string
}

variable "container_cpu" {
  description = "vCPU allocation for the container"
  type        = string
  default     = "1.0"
}

variable "container_memory" {
  description = "Memory allocation (GB) for the container"
  type        = string
  default     = "2.0"
}

variable "commands" {
  description = "Container `commands` (REPLACES the image entrypoint). Rendered by the caller — the Traefik child inlines its --hub.token here, whoami passes [\"/whoami\", \"--verbose\"]."
  type        = list(string)
  default     = []
}

variable "exposed_ports" {
  description = "Group-level `exposed_port` blocks (all TCP). A private container group must declare every port it serves. Empty means no group-level exposed_port blocks (whoami relies on container `ports` only)."
  type        = list(number)
  default     = []
}

variable "volumes" {
  description = "Secret volumes mounted into the container. Rendered by the caller (the Traefik child mounts its file-provider config as a secret volume; whoami mounts none). `secret` maps a file name to its base64-encoded content."
  type = list(object({
    name       = string
    mount_path = string
    secret     = map(string)
  }))
  default = []
}

variable "common_tags" {
  description = "Tags applied to every container group, merged UNDER each group's per-group tags (per-group wins on collision)"
  type        = map(string)
  default     = {}
}

variable "otlp_gate_address" {
  description = "OTLP collector base URL (e.g. https://collector.example.com). When set, an init container blocks the workload from starting until that endpoint ACCEPTS an OTLP write — the container-native form of cloud-init-snippets/otlp-collector-gate.sh.tpl, which every VM leg already runs. Empty disables the gate. Set it whenever the workload exports telemetry: a container that starts against a collector that is not up yet, or against a stale DNS record still pointing at a destroyed load balancer, goes dark for 30-45 minutes before it recovers on its own — long enough to make the service map a coin flip, and terraform-side ordering cannot fix it."
  type        = string
  default     = ""
}

variable "otlp_gate_image" {
  description = "Image the OTLP gate init container runs. Needs only a shell and curl — the workload images (Hub, whoami) are scratch, which is why the probe cannot live inside them. Defaults to an MCR image ON PURPOSE: ACI's anonymous pulls from Docker Hub are rate-limited, and a gate that cannot pull is a group that never starts. Measured 2026-08-11 on azure-unified-ingress, creating a group from curlimages/curl: 'RegistryErrorResponse: An error response is received from the docker registry index.docker.io'. MCR is Azure-native and imposes no such limit."
  type        = string
  default     = "mcr.microsoft.com/azurelinux/base/core:3.0"
}
