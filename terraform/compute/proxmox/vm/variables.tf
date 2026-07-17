# =============================================================================
# compute/proxmox/vm — inputs
# =============================================================================
# The shared QEMU-VM primitive both traefik/proxmox-vm (one gateway VM) and
# apps/whoami/proxmox (N whoami VMs) compose. Pure infra: it clones a
# cloud-init-enabled template, uploads the caller-rendered user-data as a PVE
# snippet, and boots the VM. It owns NO role config — user_data and the Notes
# description arrive as opaque per-instance strings.
# =============================================================================

variable "node_name" {
  description = "Name of the Proxmox VE node the VMs are created on"
  type        = string
}

variable "datastore_id" {
  description = "Datastore backing the VMs' disks and cloud-init drives (e.g. local-lvm)"
  type        = string
}

variable "snippet_datastore_id" {
  description = "Datastore the cloud-init user-data snippets are uploaded to (Snippets content type must be enabled; uploads ride the bpg provider's SSH access)"
  type        = string
  default     = "local"
}

variable "bridge" {
  description = "Name of the Linux bridge each VM's NIC joins (DHCP is assumed; the parent dials the guest IP the QEMU agent reports)"
  type        = string
  default     = "vmbr0"
}

variable "template_vm_id" {
  description = "VMID of the template to clone. Provide this OR template_name. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template with qemu-guest-agent (the agent reports the guest IP)."
  type        = number
  default     = 0
}

variable "template_name" {
  description = "Name of the template to clone (resolved to a VMID on the node). Takes precedence over template_vm_id."
  type        = string
  default     = ""
}

variable "num_cpus" {
  description = "vCPU count per VM"
  type        = number
  default     = 2
}

variable "cpu_type" {
  description = "QEMU CPU type. `host` passes the node's CPU through; pick a named model when live migration matters."
  type        = string
  default     = "host"
}

variable "memory" {
  description = "Memory in MB per VM"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk size in GB. Must be at least the template's disk (Proxmox can't shrink on clone)."
  type        = number
  default     = 20
}

variable "disk_interface" {
  description = "Interface of the template's disk to resize (the standard cloud-image import recipe attaches it as scsi0)"
  type        = string
  default     = "scsi0"
}

variable "snippet_name_prefix" {
  description = "Prefix prepended to each snippet's file name (before the instance key and content hash). traefik/proxmox-vm passes \"\" (files are `<key>-<hash>.cloud-config.yaml`); apps/whoami/proxmox passes \"whoami-\"."
  type        = string
  default     = ""
}

variable "instances" {
  description = "Map of VMs to create, keyed by VM name (used as the VM's `name` and the snippet file name stem). user_data is the already-rendered cloud-init snippet (opaque); description is the guest Notes/description (null = unset)."
  type = map(object({
    user_data   = string
    description = optional(string)
  }))
  default = {}
}
