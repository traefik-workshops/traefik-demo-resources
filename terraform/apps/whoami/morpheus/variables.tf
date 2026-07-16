variable "apps" {
  description = "Map of applications to deploy to Morpheus instances. Each app can have multiple replicas. Same shape as apps/whoami/vsphere: { name = { replicas, port, name, environment, traefik_labels } } — `traefik_labels` (dotted Traefik label -> value) lands 1:1 as instance TAGS (the Hub morpheus provider reads every traefik.* tag); optional `environment` (map) is merged over the module-level `environment` into the container. The gomorpheus-era per-app `labels` entry (Morpheus LABELS) is NO LONGER APPLIED — hpe_morpheus_instance (HPE/hpe v1.5.0) has no labels attribute — and a non-empty value now fails a precondition; set labels via the appliance instead."
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
  description = "Provision type CODE the plan is looked up under (the hpe_morpheus_service_plan data source filters by provision_type_code; \"kvm\" for MVM / HPE VM Essentials clouds — the gomorpheus-era value here was the NAME \"KVM\"). Empty = match the plan by name alone."
  default     = "kvm"
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

# tflint-ignore: terraform_unused_declarations # deliberate compat shim: validated-empty (HPE/hpe has no labels attribute)
variable "morpheus_labels" {
  type        = list(string)
  description = "MUST STAY EMPTY: the HPE/hpe provider's hpe_morpheus_instance exposes NO labels attribute (checked at v1.5.0; gomorpheus's morpheus_mvm_instance did), so Morpheus labels can't be applied from terraform anymore. The variable is kept (and validated empty) so existing callers passing [] keep working; set labels in the appliance instead."
  default     = []

  validation {
    condition     = length(var.morpheus_labels) == 0
    error_message = "morpheus_labels cannot be applied: hpe_morpheus_instance (HPE/hpe v1.5.0) has no labels attribute — the gomorpheus labels feature has no HPE equivalent yet. Leave empty and set labels via the appliance."
  }
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
  default     = "ghcr.io/zalbiraw/whoami:latest"
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

variable "instance_type_id" {
  type        = number
  description = "Literal instance-type id, bypassing the name lookup. REQUIRED on HPE VM Essentials: the hpe_morpheus_instance_type data source calls /api/library/instance-types, which 403s (templates=false) at PLAN time. null = resolve by name (full Morpheus, where the Library is licensed)."
  default     = null
}

variable "instance_layout_id" {
  type        = number
  description = "Literal layout id, bypassing the name lookup. REQUIRED on HPE VM Essentials (see instance_type_id). Also disambiguates: \"Single KVM VM\" is NOT unique — Ubuntu carries several. null = resolve by name."
  default     = null
}

variable "resource_pool_id" {
  type        = string
  description = "Literal resource-pool id, bypassing the name lookup. REQUIRED on HPE VM Essentials: it has no ResourcePool records (/api/resource-pools -> total=0) — the HVM cluster is a synthetic \"pool-<clusterId>\" served only by the zonePools option source, so the data source fails at PLAN time with \"found 0 resourcePools\". null = resolve by name (full Morpheus)."
  default     = null
}

variable "enable_provisioning_workflow" {
  type        = bool
  description = "Wrap the bootstrap task in a Morpheus PROVISIONING WORKFLOW (a task-set) and attach it to each instance via task_set_id — the native path, which runs the bootstrap at postProvision. Requires features.workflows: HPE VM Essentials does NOT have it (POST /api/task-sets -> 403 \"Feature Not Included for the Applied License\", and the 403 fires before body validation). Set FALSE on VME and execute the task DIRECTLY instead — POST /api/tasks/{id}/execute is ungated (it answers 404 for a bogus id, not 403), and the task resource itself is fine (features.tasks=true). When false the CALLER owns triggering the bootstrap after provisioning; the module exposes bootstrap_task_ids for exactly that."
  default     = true
}
