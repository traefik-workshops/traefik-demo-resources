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
  description = "Extra guestinfo extraConfig entries merged onto each VM, keyed by instance key (e.g. { \"<app>-1\" = { \"guestinfo.role\" = \"worker\" } }). Empty per-key map adds nothing."
  type        = map(map(string))
  default     = {}
}

variable "tags" {
  type        = map(list(string))
  default     = {}
  description = "vCenter tag IDs to attach, keyed by instance key. The vsphere provider has no standalone attach resource — tags ride the VM resource itself, so they are set at create. Organisational only: the Hub vsphere provider does not read tags (see var.annotation)."
}

variable "annotation" {
  type        = map(string)
  default     = {}
  description = "VM Notes (config.annotation) per instance key. The Hub vsphere provider reads a LINE-FORMAT label block from it — one `traefik.<key>=<value>` per line — so the caller renders the block here. An absent key leaves the Notes untouched. Updatable in place: a label change is a reconfigure, never a replacement."
}

variable "extra_networks" {
  type        = list(string)
  default     = []
  description = "Additional portgroups to attach, in order, after var.network. Used for multi-homed VMs — the demo's router VM sits on the public VLAN and the internal one. Guest interface names follow the attach order (ens192, ens224, ...)."
}

variable "network_config" {
  type        = any
  default     = {}
  description = "Per-instance cloud-init network-config v2, keyed by instance key. Merged into the guestinfo metadata, so it is applied at BOOT — before cloud-init installs packages or runs commands. That ordering is the point: a VM on a network without DHCP has no connectivity during the package stage, and anything configured later (a netplan file written by write_files, applied in runcmd) comes far too late to save the apt run. Empty = DHCP."
}
