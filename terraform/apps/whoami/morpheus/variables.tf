variable "apps" {
  description = "Map of applications to deploy to Morpheus instances. Each app can have multiple replicas. Same shape as apps/whoami/vsphere plus `labels`: { name = { replicas, port, name, environment, traefik_labels, labels } } — `traefik_labels` (dotted Traefik label -> value) lands 1:1 as instance TAGS (the Hub morpheus provider reads every traefik.* tag); optional `labels` (list of strings) are Morpheus LABELS for the provider's constraints; optional `environment` (map) is merged over the module-level `environment` into the container."
  type        = any
  default     = {}
}

# --- Morpheus placement -------------------------------------------------------
variable "cloud" {
  type        = string
  description = "Name of the Morpheus cloud (e.g. the MVM/HVM cloud registered on the appliance) the instances are provisioned into"
}

variable "group" {
  type        = string
  description = "Name of the Morpheus group the instances belong to"
}

variable "instance_type" {
  type        = string
  description = "Name of the Morpheus instance type to provision from (e.g. \"Ubuntu\"). Must boot a cloud-init-enabled Linux image — the Morpheus agent (installed via cloud-init) runs the whoami bootstrap."
  default     = "Ubuntu"
}

variable "instance_layout" {
  type        = string
  description = "Name of the instance layout under instance_type (e.g. \"Single KVM VM\")"
}

variable "instance_layout_version" {
  type        = string
  description = "Version of the instance layout (e.g. \"24.04\") — disambiguates layouts sharing a name. Empty = match by name alone."
  default     = ""
}

variable "plan" {
  type        = string
  description = "Name of the service plan — the plan IS the VM shape on Morpheus (no per-module cpu/memory knobs); a small one fits whoami (e.g. \"1 CPU, 2GB Memory\")"
}

variable "plan_provision_type" {
  type        = string
  description = "Provision type NAME the plan is looked up under (the morpheus_plan data source requires it; \"KVM\" for MVM / HPE VM Essentials clouds)"
  default     = "KVM"
}

variable "resource_pool_name" {
  type        = string
  description = "Name of the resource pool (the MVM/HVM cluster) to provision the instances to"
}

variable "network" {
  type        = string
  description = "Name of the Morpheus network the instance NICs join (DHCP is assumed; the Traefik child dials each instance's primary IP). Empty = the layout's default network selection."
  default     = ""
}

variable "network_interface_type_id" {
  type        = number
  description = "Morpheus network interface TYPE ID for the NICs (required when network is set)"
  default     = null
}

variable "root_volume" {
  type = object({
    size         = number
    datastore_id = number
    storage_type = optional(number, 1)
    name         = optional(string, "root")
  })
  description = "Optional explicit root volume {size (GB), datastore_id, storage_type, name}. null = the layout/plan defaults."
  default     = null
}

variable "morpheus_labels" {
  type        = list(string)
  description = "Morpheus labels attached to EVERY instance (per-app `labels` entries are appended) — what the Hub morpheus provider's constraints match, as label=true pairs plus the `name` pseudo-label"
  default     = []
}

variable "name_prefix" {
  type        = string
  description = "Prefix for the per-app bootstrap task/workflow names (appliance-level library items — two stacks sharing a prefix and app names on one appliance collide)"
  default     = "whoami"
}

# --- Workload ---------------------------------------------------------------
variable "whoami_image" {
  description = "Whoami image to docker-run on each instance. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "docker.io/zalbiraw/whoami:latest"
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
