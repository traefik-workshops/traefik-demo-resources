# =============================================================================
# compute/vsphere/vm — shared vSphere VM fleet
# =============================================================================
# Owns the vsphere_virtual_machine resource (and the datacenter/datastore/
# cluster/resource_pool/network/template data lookups) shared by traefik/
# vsphere-vm (one gateway VM) and apps/whoami/vsphere (N workload VMs). It is
# role-agnostic: cloud-init is rendered by the caller and handed in as opaque
# `user_data`; the caller's Traefik-label workload config arrives as opaque
# `extra_config` guestinfo entries.
# =============================================================================

# --- Instance expansion -----------------------------------------------------
variable "apps" {
  description = "Map of apps to expand into VMs. Each app yields `replicas` VMs keyed `<app>-<replica>` (mirrors compute/aws/ec2). The gateway calls with one app/replica; whoami with N. `user_data` and `extra_config` are keyed by those same instance keys."
  type = map(object({
    replicas = optional(number, 1)
  }))
  default = {}
}

variable "replica_start_index" {
  description = "Starting index for replica numbering (Default: 1). Instance keys are `<app>-<replica_idx + replica_start_index>`."
  type        = number
  default     = 1
}

# --- vSphere placement -------------------------------------------------------
variable "datacenter" {
  description = "Name of the vSphere datacenter the VMs are created in"
  type        = string
}

variable "datastore" {
  description = "Name of the datastore backing the VMs' disks"
  type        = string
}

variable "cluster" {
  description = "Name of the compute cluster to place the VMs in (its root resource pool). Provide this OR resource_pool."
  type        = string
  default     = ""

  validation {
    condition     = var.cluster != "" || var.resource_pool != ""
    error_message = "Provide cluster or resource_pool."
  }
}

variable "resource_pool" {
  description = "Name/path of the resource pool to place the VMs in. Takes precedence over cluster."
  type        = string
  default     = ""
}

variable "network" {
  description = "Name of the port group / network the VM NICs join (DHCP is assumed; the Traefik child dials each VM's guest IP)"
  type        = string
}

variable "template" {
  description = "Name of the VM template to clone. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (e.g. imported from ubuntu-24.04-server-cloudimg-amd64.ova) — a plain installer-built template ignores the guestinfo userdata and the workload never starts."
  type        = string
}

variable "folder" {
  description = "VM folder to place the VMs in. Empty = the datacenter root."
  type        = string
  default     = ""
}

# --- VM shape ---------------------------------------------------------------
variable "num_cpus" {
  description = "vCPU count per VM"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MB per VM"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk size in GB. Grown to at least the template's disk (vSphere can't shrink on clone)."
  type        = number
  default     = 20
}

# --- Workload (opaque, built by the caller) ---------------------------------
variable "user_data" {
  description = "Rendered cloud-init user-data per instance, keyed by instance key (`<app>-<replica>`). base64-encoded into the VM's `guestinfo.userdata` extraConfig entry. Opaque to this module — the caller renders it."
  type        = map(string)
  default     = {}
}

variable "extra_config" {
  description = "Extra guestinfo extraConfig entries merged onto each VM, keyed by instance key. The caller builds the vsphere provider's workload config here — e.g. { \"<app>-1\" = { \"guestinfo.traefik\" = jsonencode(labels) } }. Empty per-key map adds nothing."
  type        = map(map(string))
  default     = {}
}
