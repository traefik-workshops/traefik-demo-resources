# =============================================================================
# compute/proxmox/lxc — inputs
# =============================================================================
# The shared LXC-container primitive both traefik/proxmox-lxc (one gateway
# container, static-addressed) and apps/whoami/proxmox (N whoami containers,
# DHCP) compose. Pure infra: it creates the unprivileged, nesting-enabled
# container. The in-container install (Hub binary / whoami binary via
# pct-exec) is role config and stays in the callers, which read the container
# id from this module's outputs.
# =============================================================================

variable "node_name" {
  description = "Name of the Proxmox VE node the containers are created on"
  type        = string
}

variable "datastore_id" {
  description = "Datastore backing the containers' root filesystems (e.g. local-lvm)"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Name of the Linux bridge each container's NIC (eth0) joins"
  type        = string
  default     = "vmbr0"
}

variable "template_file_id" {
  description = "OS template file ID, e.g. \"local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst\". Must be a systemd Debian template — the workload rides its init."
  type        = string
  default     = ""
}

variable "num_cpus" {
  description = "vCPUs per container"
  type        = number
  default     = 2
}

variable "memory" {
  description = "RAM (MB) per container"
  type        = number
  default     = 1024
}

variable "disk_size" {
  description = "Root filesystem size (GB) per container"
  type        = number
  default     = 4
}

variable "instances" {
  description = "Map of containers to create, keyed by container name (used as the initialization hostname). description is the guest Notes/description (null = unset). ip_address is a CIDR for a STATIC address or \"dhcp\" (default); gateway is required alongside a static address and must be null for DHCP. dns (optional) writes an initialization dns block — required for static addresses that must reach a specific lab resolver."
  type = map(object({
    description = optional(string)
    ip_address  = optional(string, "dhcp")
    gateway     = optional(string)
    dns = optional(object({
      servers = list(string)
      domain  = optional(string)
    }))
  }))
  default = {}
}
