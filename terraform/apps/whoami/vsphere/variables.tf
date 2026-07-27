variable "apps" {
  description = "Map of applications to deploy to vSphere VMs. Each app can have multiple replicas. { name = { replicas, port, name, environment, services } } — `services` is a list of vCenter TAG names (in var.service_tag_category) naming the Traefik services these VMs back; each VM is attached to every one, which is how the Hub vsphere provider discovers them. Optional `environment` (map) is merged over the module-level `environment` into the container. `traefik_labels` is accepted but INERT: the vCenter-native provider reads tags, not per-VM labels."
  type        = any
  default     = {}
}

# --- vSphere placement ----------------------------------------------------
variable "datacenter" {
  type        = string
  description = "Name of the vSphere datacenter the VMs are created in"
}

variable "datastore" {
  type        = string
  description = "Name of the datastore backing the VMs' disks"
}

variable "cluster" {
  type        = string
  description = "Name of the compute cluster to place the VMs in (its root resource pool). Provide this OR resource_pool."
  default     = ""

  validation {
    condition     = var.cluster != "" || var.resource_pool != ""
    error_message = "Provide cluster or resource_pool."
  }
}

variable "resource_pool" {
  type        = string
  description = "Name/path of the resource pool to place the VMs in. Takes precedence over cluster."
  default     = ""
}

variable "network" {
  type        = string
  description = "Name of the port group / network the VM NICs join (DHCP is assumed; the Traefik child dials each VM's guest IP)"
}

variable "template" {
  type        = string
  description = "Name of the VM template to clone. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (e.g. imported from ubuntu-24.04-server-cloudimg-amd64.ova) — a plain installer-built template ignores the guestinfo userdata and whoami never starts."
}

variable "folder" {
  type        = string
  description = "VM folder to place the VMs in. Empty = the datacenter root."
  default     = ""
}

# --- VM shape ---------------------------------------------------------------
variable "num_cpus" {
  type        = number
  description = "vCPU count per whoami VM"
  default     = 1
}

variable "memory" {
  type        = number
  description = "Memory in MB per whoami VM"
  default     = 1024
}

variable "disk_size" {
  type        = number
  description = "Disk size in GB. Grown to at least the template's disk (vSphere can't shrink on clone)."
  default     = 20
}

# --- Workload ---------------------------------------------------------------
variable "whoami_image" {
  description = "Whoami image to docker-run on each VM. Untagged references get `:` + whoami_version appended."
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

variable "service_tag_ids" {
  type        = map(string)
  default     = {}
  description = "vCenter tag NAME -> tag ID, covering every name used in the apps' `services` lists. Passed in because the caller owns the category and tags; looking them up here would fail on a first apply, when they do not exist yet."
}

variable "service_tag_category" {
  type        = string
  default     = "TraefikServiceName"
  description = "vCenter tag CATEGORY naming Traefik services. Each app's `services` list names tags in this category, and every VM of that app is attached to each — that is how the Hub vsphere provider learns which services a VM backs. The category must exist and be MULTIPLE-cardinality (a VM backing three LB-strategy services carries three tags); the caller owns creating it."
}
