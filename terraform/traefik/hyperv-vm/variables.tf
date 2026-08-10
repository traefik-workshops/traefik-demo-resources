# =============================================================================
# Hyper-V-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/ec2, traefik/vsphere-vm and traefik/proxmox-vm (same names, so demo
# code reads identically across platforms).
# =============================================================================

variable "host_winrm" {
  description = "WinRM HTTPS access to the Hyper-V HOST the gateway VM is created on (see compute/hyperv/vm). Creation plane only — the DISCOVERY credential (var.hyperv_provider + var.hyperv_password) targets the SCVMM server, a different machine and a different account."
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
  description = "Hyper-V virtual switch the VM's NIC joins (the parent dials this VM's static IP :9443 in-network)."
  default     = "traefik-lab"
}

variable "parent_vhdx_path" {
  type        = string
  description = "Golden parent VHDX the differencing disk chains to — a generic Ubuntu CLOUD IMAGE conversion (never -azure.vhd) with linux-cloud-tools baked in (see compute/hyperv/vm)."
}

variable "workdir" {
  type        = string
  description = "Host directory the VM's seed + differencing disk live under."
  default     = "C:\\traefik-lab"
}

variable "vm_name" {
  description = "Base name for the Traefik VM (instance key becomes <vm_name>-1, the traefik/ec2 scheme)"
  type        = string
  default     = "traefik"
}

variable "num_cpus" {
  description = "vCPU count"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MB (static memory — the compute module disables dynamic memory)"
  type        = number
  default     = 4096
}

# --- Static addressing ---------------------------------------------------------
variable "ip_address" {
  type        = string
  description = "Static CIDR the gateway takes via its NoCloud network-config (e.g. 10.99.0.20/24). PLAN-KNOWN by design: the hub's multicluster `children` map dials https://<this>:9443, so a single apply wires the uplink — no PENDING second pass."

  validation {
    condition     = can(cidrhost(var.ip_address, 0))
    error_message = "ip_address must be CIDR notation (e.g. 10.99.0.20/24)."
  }
}

variable "gateway" {
  type        = string
  description = "Default gateway for the VM — the Hyper-V internal NAT switch's host-side address (e.g. 10.99.0.1)."
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers for the VM (the lab router's dnsmasq on the hyperv demo). Static guests get no DHCP: without this the gateway can resolve neither its image registry nor collector.<domain>, and its cloud-init self-gate stalls."
  default     = []
}

variable "extra_files" {
  type = list(object({
    path    = string
    content = string
  }))
  description = "Extra files to write to the VM at cloud-init time"
  default     = []
}

variable "mount_docker_socket" {
  type        = bool
  description = "Bind /var/run/docker.sock into the preview-mode Traefik container so its docker provider can reach the local daemon. Root-equivalent access to the host, so leave it off for any gateway that is not the docker-provider leg."
  default     = false
}

variable "extra_runcmd" {
  type        = list(string)
  description = "Extra shell blocks appended to cloud-init runcmd, after Docker is installed and before traefik-hub starts. Used to run workload containers on the gateway VM itself (the docker-provider leg)."
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

variable "hyperv_provider" {
  description = "Native first-party Hub Hyper-V discovery provider — rendered as `--hub.providers.hyperv.*` (like ec2/azurevm/gce/proxmox). SCVMM-BASED: vmm_server is the SCVMM MANAGEMENT server (never a Hyper-V host — standalone hosts have no API and are not dialed), reached over WinRM HTTPS (NTLM; insecure_skip_verify defaults true for the lab's self-signed listener). username must be domain-qualified (e.g. LAB\\\\traefik-discovery), a member of VMM's Read-Only Administrator user role that can open raw WinRS shells on the VMM server (non-admins need the A;;GXGR RootSDDL ACE — Remote Management Users alone is NOT sufficient); the password rides the separate sensitive var.hyperv_password. `cloud` (a VMM Cloud name) and `host_group` (a VMHostGroup path like \"All Hosts\\\\Production\") each scope one gateway to one estate slice — the enterprise delegation story — and are MUTUALLY EXCLUSIVE; both empty discovers the whole estate. ip_mode private/public both resolve to the VMM-reported guest address on-prem; `label` reads traefik.hyperv.ip — the per-VM escape hatch for KVP-less guests."
  type = object({
    enabled              = optional(bool, true)
    vmm_server           = optional(string, "")
    port                 = optional(number, 5986)
    username             = optional(string, "")
    refresh_seconds      = optional(number, 30)
    insecure_skip_verify = optional(bool, true)
    cloud                = optional(string, "")
    host_group           = optional(string, "")
    constraints          = optional(string, "")
    default_rule         = optional(string, "")
    exposed_by_default   = optional(bool, false)
    ip_mode              = optional(string, "private")
  })
  default = {}

  validation {
    condition     = !var.hyperv_provider.enabled || (var.hyperv_provider.vmm_server != "" && var.hyperv_provider.username != "")
    error_message = "hyperv_provider.vmm_server and hyperv_provider.username are required when enabled (WinRM has no ambient identity)."
  }

  validation {
    condition     = var.hyperv_provider.cloud == "" || var.hyperv_provider.host_group == ""
    error_message = "hyperv_provider.cloud and hyperv_provider.host_group are mutually exclusive (the provider's Init refuses both)."
  }
}

variable "hyperv_password" {
  description = "Password of the WinRM account the native hyperv provider discovers with (pairs with hyperv_provider.username → --hub.providers.hyperv.password). Point it at the READ-ONLY discovery account, not a VMM administrator."
  type        = string
  sensitive   = true
  default     = ""
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
  description = "Enable Traefik Hub Preview features (runs the image as a docker container). Needed while the hyperv provider ships only in the demo-hyperv build (a mutable pre-release tag the cloud-init re-pulls on every start) — not for anything about Hyper-V itself."
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
  description = "Additional Traefik plugins (hyperv discovery is a native first-party provider, wired via var.hyperv_provider — not a plugin)"
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

# NB: no enable_dashboard_discovery here, unlike traefik/proxmox-vm. Self-
# registration would mean writing this VM's own labels into its SCVMM
# Description — a VMM-side WRITE this module deliberately does not carry a
# credential for. Advertise the dashboard over a file-rule uplink instead
# (file_provider_config + custom_ports), which is what the hyperv demo does.

variable "ssh_public_key" {
  type        = string
  description = "Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt."
  default     = ""
}
