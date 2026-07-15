variable "apps" {
  description = "Map of applications to deploy to Proxmox guests. Same shape as apps/whoami/vsphere plus a `type` field: { name = { replicas, type (\"vm\"|\"lxc\", default vm), port, name, environment, traefik_labels } }. `traefik_labels` (dotted Traefik label -> value) is rendered in the NX211 plugin's LINE format — one `key=value` per line — into the guest's Notes/description. NB the plugin registers ONE server per guest and same-named services overwrite each other, so give each guest UNIQUE service names (compose spreads upstream with a weighted file-provider service)."
  type        = any
  default     = {}
}

# --- Proxmox placement --------------------------------------------------------
variable "node_name" {
  type        = string
  description = "Name of the Proxmox VE node the guests are created on"
}

variable "datastore_id" {
  type        = string
  description = "Datastore backing the guests' disks and cloud-init drives (e.g. local-lvm)"
}

variable "snippet_datastore_id" {
  type        = string
  description = "Datastore the cloud-init user-data snippets are uploaded to (Snippets content type must be enabled; uploads ride the provider's SSH access)"
  default     = "local"
}

variable "bridge" {
  type        = string
  description = "Name of the Linux bridge the guests' NICs join (DHCP is assumed; the Traefik child dials each guest's IP)"
  default     = "vmbr0"
}

variable "template_vm_id" {
  type        = number
  description = "VMID of the template QEMU apps clone. Provide this OR template_name (only needed when at least one app has type = \"vm\"). Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template with qemu-guest-agent — the agent is what reports guest IPs, both to terraform and to the discovery plugin."
  default     = 0
}

variable "template_name" {
  type        = string
  description = "Name of the template QEMU apps clone (resolved to a VMID on the node). Takes precedence over template_vm_id."
  default     = ""
}

# --- Guest shape -----------------------------------------------------------------
variable "num_cpus" {
  type        = number
  description = "vCPU count per whoami guest (VMs and containers)"
  default     = 1
}

variable "cpu_type" {
  type        = string
  description = "QEMU CPU type for VMs. `host` passes the node's CPU through; pick a named model when live migration matters."
  default     = "host"
}

variable "memory" {
  type        = number
  description = "Memory in MB per whoami guest (VMs and containers)"
  default     = 1024
}

variable "disk_size" {
  type        = number
  description = "VM disk size in GB. Must be at least the template's disk (Proxmox can't shrink on clone)."
  default     = 20
}

variable "disk_interface" {
  type        = string
  description = "Interface of the template's disk to resize (the standard cloud-image import recipe attaches it as scsi0)"
  default     = "scsi0"
}

variable "lxc_disk_size" {
  type        = number
  description = "Root filesystem size in GB for LXC containers"
  default     = 8
}

# --- Workload (QEMU VMs) ------------------------------------------------------------
variable "whoami_image" {
  description = "Whoami image docker-run on each VM (type = \"vm\"). LXC apps run the binary EXTRACTED from lxc_whoami_image instead (no docker in the container). Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "ghcr.io/zalbiraw/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables passed to every whoami (docker -e on VMs, the systemd unit on LXC), e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. With the default lxc_whoami_image (the fork), the LXC binary honors OTEL_* too; only the upstream-release fallback ignores them. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}

# --- Workload (LXC containers) --------------------------------------------------------
variable "lxc_template_file_id" {
  type        = string
  description = "OS template file ID LXC apps are created from, e.g. \"local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst\" (a systemd Debian template — the whoami unit rides its init). Required when any app has type = \"lxc\"."
  default     = ""
}

variable "gateway" {
  type        = string
  description = "Default gateway for LXC apps that pin a static ip_address (the internal bridge's address, e.g. 10.10.10.1). Unused for DHCP apps and for QEMU VMs (cloud-init DHCPs those)."
  default     = ""
}

variable "lxc_whoami_image" {
  type        = string
  description = "OCI image whose whoami binary (Entrypoint /whoami) is EXTRACTED with crane and run raw inside LXC containers — no docker-in-LXC. Default is the OTel-instrumented fork (ghcr.io/zalbiraw/whoami), so the LXC leg emits OTLP like the QEMU/k8s whoami and shows as its own service-graph node. Set to \"\" to fall back to the upstream traefik/whoami release binary (lxc_whoami_version), which has no tracing."
  default     = "ghcr.io/zalbiraw/whoami:latest"
}

variable "lxc_whoami_version" {
  type        = string
  description = "traefik/whoami RELEASE tag whose linux_amd64 binary is installed inside LXC containers ONLY when lxc_whoami_image is \"\" (the upstream binary fallback — no OTLP tracing)."
  default     = "v1.11.0"
}

variable "crane_version" {
  type        = string
  description = "go-containerregistry release whose static `crane` binary the LXC setup fetches to export lxc_whoami_image's rootfs (no docker needed on the node or in the container)."
  default     = "v0.20.2"
}

variable "node_ssh" {
  description = "SSH access to the Proxmox NODE, used to `pct push`/`pct exec` the whoami install into LXC containers (LXC has no cloud-init user-data path). Required when any app has type = \"lxc\"; null otherwise."
  type = object({
    host        = string
    user        = optional(string, "root")
    private_key = string
  })
  default   = null
  sensitive = true
}
