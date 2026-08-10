variable "apps" {
  description = "Map of applications to deploy as Hyper-V VMs. Each value: { replicas, ip_addresses (list of static CIDRs, ONE PER REPLICA — Hyper-V has no plan-readable discovery, so the caller plans the fleet's addresses), port, name, environment, traefik_labels }. `traefik_labels` (dotted Traefik label -> value) is rendered as LINE-format `traefik.key=value` labels into the SCVMM VM **Description** (VMM-side; the host Notes field is never read). The native provider MERGES same-named services across VMs — identical labels on N replicas fold into one N-server load balancer (vsphere/EC2-style, NOT proxmox's one-service-per-guest) — so a fleet SHARES one label block, and per-service `loadbalancer.strategy` labels (leasttime/hrw) apply to the whole merged pool."
  type = map(object({
    replicas       = number
    ip_addresses   = list(string)
    port           = optional(number, 80)
    name           = optional(string, "")
    environment    = optional(map(string), {})
    traefik_labels = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for name, cfg in var.apps : length(cfg.ip_addresses) == cfg.replicas])
    error_message = "Every app needs exactly one static ip_addresses entry per replica (addressing is planned, not discovered)."
  }
}

# --- Hyper-V placement (host-side plane, threaded to compute/hyperv/vm) --------
variable "host_winrm" {
  description = "WinRM HTTPS access to the Hyper-V HOST the VMs are created on (see compute/hyperv/vm). This is the CREATION plane — labels never travel over it."
  type = object({
    host     = string
    port     = optional(number, 5986)
    username = string
    password = string
    https    = optional(bool, true)
    insecure = optional(bool, true)
    use_ntlm = optional(bool, true)
    timeout  = optional(string, "10m")
  })
  sensitive = true
}

variable "switch_name" {
  type        = string
  description = "Hyper-V virtual switch the VMs' NICs join."
  default     = "traefik-lab"
}

variable "parent_vhdx_path" {
  type        = string
  description = "Golden parent VHDX every VM's differencing disk chains to (see compute/hyperv/vm — cloud image, never -azure.vhd, linux-cloud-tools baked in)."
}

variable "workdir" {
  type        = string
  description = "Host directory the VMs' seeds + differencing disks live under."
  default     = "C:\\traefik-lab"
}

# --- SCVMM (VMM-side plane: the label writer) -----------------------------------
variable "vmm" {
  description = "WinRM HTTPS access to the SCVMM MANAGEMENT SERVER, where `Set-SCVirtualMachine -Description` writes each VM's label block. Needs a VMM-WRITE-capable account (an Administrator or a delegated role with VM write on these VMs) — deliberately NOT the gateway's read-only discovery credential. Label changes re-run only this writer, never a VM replacement."
  type = object({
    host     = string
    port     = optional(number, 5986)
    username = string
    password = string
    timeout  = optional(string, "10m")
  })
  sensitive = true
}

# --- Guest shape -----------------------------------------------------------------
variable "num_cpus" {
  type        = number
  description = "vCPU count per whoami VM"
  default     = 1
}

variable "memory" {
  type        = number
  description = "Memory in MB per whoami VM (static memory)"
  default     = 1024
}

variable "gateway" {
  type        = string
  description = "Default gateway for the VMs — the Hyper-V internal NAT switch's host-side address (e.g. 10.99.0.1)."
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers for the VMs (the lab router's dnsmasq on the hyperv demo). Static guests get no DHCP: forgetting this leaves whoami unable to resolve its registry or OTLP collector."
  default     = []
}

# --- Workload ---------------------------------------------------------------------
variable "whoami_image" {
  description = "Whoami image docker-run on each VM. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "ghcr.io/traefik-workshops/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables passed to every whoami (docker -e), e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}
