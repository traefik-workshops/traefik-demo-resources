# =============================================================================
# Proxmox-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/ec2 and traefik/vsphere-vm (same names, so demo code reads
# identically across platforms).
# =============================================================================

variable "node_name" {
  description = "Name of the Proxmox VE node the VM is created on"
  type        = string
}

variable "datastore_id" {
  description = "Datastore backing the VM's disk and cloud-init drive (e.g. local-lvm)"
  type        = string
}

variable "snippet_datastore_id" {
  description = "Datastore the cloud-init user-data snippet is uploaded to (Snippets content type must be enabled; uploads ride the bpg provider's SSH access)"
  type        = string
  default     = "local"
}

variable "bridge" {
  description = "Name of the Linux bridge the VM's NIC joins (DHCP is assumed; the parent dials the VM's guest IP :9443 in-network)"
  type        = string
  default     = "vmbr0"
}

variable "template_vm_id" {
  description = "VMID of the template to clone. Provide this OR template_name. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template with qemu-guest-agent (the agent reports the guest IP the parent dials)."
  type        = number
  default     = 0
}

variable "template_name" {
  description = "Name of the template to clone (resolved to a VMID on the node). Takes precedence over template_vm_id."
  type        = string
  default     = ""

  validation {
    condition     = var.template_name != "" || var.template_vm_id != 0
    error_message = "Provide template_vm_id or template_name."
  }
}

variable "vm_name" {
  description = "Base name for the Traefik VM"
  type        = string
  default     = "traefik"
}

variable "num_cpus" {
  description = "vCPU count"
  type        = number
  default     = 2
}

variable "cpu_type" {
  description = "QEMU CPU type. `host` passes the node's CPU through; pick a named model when live migration matters."
  type        = string
  default     = "host"
}

variable "memory" {
  description = "Memory in MB"
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

variable "extra_labels" {
  description = "Extra Traefik labels merged into the VM's own Notes/description (on top of the dashboard self-registration labels, when enabled), rendered as the native provider's JSON label map"
  type        = map(string)
  default     = {}
}

variable "extra_files" {
  type = list(object({
    path    = string
    content = string
  }))
  description = "Extra files to write to the VM at cloud-init time"
  default     = []
}

# =============================================================================
# Performance Tuning Configuration
# =============================================================================

variable "performance_tuning" {
  description = "OS-level performance tuning parameters for high-throughput workloads"
  type = object({
    # Systemd ulimits
    limit_nofile = optional(number, 500000)

    # Sysctl network tuning
    tcp_tw_reuse        = optional(number, 1)
    tcp_timestamps      = optional(number, 1)
    rmem_max            = optional(number, 16777216)
    wmem_max            = optional(number, 16777216)
    somaxconn           = optional(number, 4096)
    netdev_max_backlog  = optional(number, 4096)
    ip_local_port_range = optional(string, "1024 65535")

    # Go runtime tuning
    gomaxprocs = optional(number, 0)   # 0 = use all CPUs
    gogc       = optional(number, 100) # default GC target percentage
    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node
  })
  default = {}
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

variable "proxmox_provider" {
  description = "Native first-party Hub Proxmox VE discovery provider — rendered as `--hub.providers.proxmox.*` (like ec2/azurevm/gce), NOT the old NX211 Yaegi plugin. No plugin download, so the VM needs no outbound internet to fetch a plugin. Proxmox has no ambient identity, so endpoint + token_id are required when enabled — the token secret rides the separate sensitive var.proxmox_api_token. insecure_skip_verify defaults true (self-signed PVE certs are the lab norm). guest_types is the KEY win over the plugin: it filters this gateway to one compute type (qemu OR lxc), so each child fronts only its own compute type instead of every child discovering every guest."
  type = object({
    enabled              = optional(bool, true)
    endpoint             = optional(string, "")
    token_id             = optional(string, "")
    refresh_seconds      = optional(number, 30)
    insecure_skip_verify = optional(bool, true)
    guest_types          = optional(list(string), []) # ["qemu"] or ["lxc"]; empty discovers both
    exposed_by_default   = optional(bool, false)
    ip_mode              = optional(string, "private")
    nodes                = optional(list(string), [])
    tag_filter           = optional(string, "")
  })
  default = {}

  validation {
    condition     = !var.proxmox_provider.enabled || (var.proxmox_provider.endpoint != "" && var.proxmox_provider.token_id != "")
    error_message = "proxmox_provider.endpoint and proxmox_provider.token_id are required when enabled (Proxmox has no ambient identity)."
  }
}

variable "proxmox_api_token" {
  description = "PVE API token SECRET the native proxmox provider authenticates with (pairs with proxmox_provider.token_id → --hub.providers.proxmox.tokenSecret). Point it at a read-only role — VM.Audit,Sys.Audit,Datastore.Audit plus VM.GuestAgent.Audit on PVE 9 (VM.Monitor on PVE 8) for guest-agent IP reads."
  type        = string
  sensitive   = true
}

variable "multicluster_provider" {
  description = "Traefik Hub multicluster provider configuration"
  type = object({
    enabled      = optional(bool, false)
    pollInterval = optional(number, null)
    pollTimeout  = optional(number, null)
    children     = optional(any, {})
  })
  default = {
    enabled = false
  }
}

# =============================================================================
# Shared Variable Declarations
# =============================================================================

# Feature Flags
variable "enable_api_gateway" {
  description = "Enable Traefik Hub API Gateway features"
  type        = bool
  default     = false
}

variable "enable_ai_gateway" {
  description = "Enable Traefik Hub AI Gateway features"
  type        = bool
  default     = false
}

variable "enable_mcp_gateway" {
  description = "Enable MCP Gateway (Claude, etc.)"
  type        = bool
  default     = false
}

variable "enable_offline_mode" {
  description = "Enable Traefik Hub Offline mode"
  type        = bool
  default     = false
}

variable "enable_preview_mode" {
  description = "Enable Traefik Hub Preview features (runs the image as a docker container). NOT needed for the proxmox plugin itself — it's a runtime plugin any released image loads — only for running a pre-release Hub build (e.g. the multicluster-uplink branch)."
  type        = bool
  default     = false
}

variable "enable_debug" {
  description = "Enable Traefik debug mode (pprof)"
  type        = bool
  default     = false
}

# Versions & Images
variable "traefik_chart_version" {
  description = "Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh)."
  type        = string
  # Chart 40.3.0 publishes hub-max v3.20.4 — the multicluster-verified pairing (matches the hub).
  default = "40.3.0"
}

variable "traefik_tag" {
  description = "Traefik OSS version tag"
  type        = string
  default     = "v3.7.4"
}

variable "traefik_hub_tag" {
  description = "Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh."
  type        = string
  default     = "v3.20.4"
}

variable "traefik_hub_preview_tag" {
  description = "Traefik Hub preview version tag"
  type        = string
  default     = ""
}

variable "custom_image_registry" {
  description = "Custom image registry"
  type        = string
  default     = ""
}

variable "custom_image_repository" {
  description = "Custom image repository"
  type        = string
  default     = ""
}

variable "custom_image_tag" {
  description = "Custom image tag"
  type        = string
  default     = ""
}

# Observability
variable "log_level" {
  description = "Log level (DEBUG, INFO, WARN, ERROR)"
  type        = string
  default     = "INFO"
}

variable "otlp_address" {
  description = "OTLP collector endpoint"
  type        = string
  default     = ""
}

variable "otlp_service_name" {
  description = "Service name for telemetry"
  type        = string
  default     = "traefik"
}

variable "enable_otlp_access_logs" {
  description = "Enable OTLP access logs"
  type        = bool
  default     = false
}

variable "enable_otlp_application_logs" {
  description = "Enable OTLP application logs"
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Enable Traefik access logs"
  type        = bool
  default     = true
}

variable "enable_otlp_metrics" {
  description = "Enable OTLP metrics"
  type        = bool
  default     = false
}

variable "enable_otlp_traces" {
  description = "Enable OTLP traces"
  type        = bool
  default     = false
}

variable "enable_prometheus" {
  description = "Enable Prometheus metrics"
  type        = bool
  default     = false
}

# Plugins & Extensions
variable "custom_plugins" {
  description = "Additional Traefik plugins (proxmox discovery is a native first-party provider now, wired via var.proxmox_provider — not a plugin)"
  type = map(object({
    moduleName = string
    version    = string
  }))
  default = {}
}

variable "custom_ports" {
  description = "Custom ports configuration. Typed `any` so it can carry a full Helm `ports.<name>` shape — e.g. a Hub multicluster uplink entrypoint { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } } — not just { port, protocol }."
  type        = any
  default     = {}
}

variable "custom_arguments" {
  description = "Additional CLI arguments for Traefik"
  type        = list(string)
  default     = []
}

variable "custom_envs" {
  description = "Custom environment variables"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "file_provider_config" {
  description = "YAML configuration for Traefik file provider"
  type        = string
  default     = ""
}

variable "file_provider_path" {
  description = "Path where the file provider config is mounted"
  type        = string
  default     = "/etc/traefik-hub/dynamic"
}

variable "enable_gitops_config" {
  description = "Deliver the file-provider dynamic.yaml by GitOps (git-pull from gitops_repo_url on a boot-gate + timer) instead of baking it into user_data — a config change then hot-reloads with NO VM replacement. Set file_provider_config empty when this is on. See terraform/config-server/git."
  type        = bool
  default     = false
}

variable "gitops_repo_url" {
  description = "Clone URL of the hub's config repo (https://git.<domain>/config.git). This gateway pulls gitops_repo_url and syncs <vm_name>/dynamic.yaml into the watch dir."
  type        = string
  default     = ""
}

# Licensing
variable "traefik_hub_token" {
  description = "Traefik Hub license token"
  type        = string
  default     = ""
  sensitive   = true
}

# Dashboard
variable "dashboard_entrypoints" {
  description = "Dashboard entry points"
  type        = list(string)
  default     = ["traefik"]
}

variable "dashboard_match_rule" {
  description = "Match rule for the Traefik dashboard router"
  type        = string
  default     = ""
}

variable "enable_dashboard" {
  description = "Enable Traefik dashboard"
  type        = bool
  default     = true
}

variable "dashboard_insecure" {
  description = "Enable insecure dashboard access (no auth)"
  type        = bool
  default     = true
}

variable "enable_dashboard_discovery" {
  description = "Self-register the Traefik VM via its own Notes labels (traefik.enable + dashboard router/service, as the native provider's JSON label map) so its OWN proxmox provider discovers the dashboard on @proxmox. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the VM isn't self-discovered at all."
  type        = bool
  default     = true
}
