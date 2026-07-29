# =============================================================================
# vSphere-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/ec2 and traefik/azure-vm (same names, so demo code reads identically
# across platforms).
# =============================================================================

variable "datacenter" {
  description = "Name of the vSphere datacenter the VM is created in"
  type        = string
}

variable "datastore" {
  description = "Name of the datastore backing the VM's disk"
  type        = string
}

variable "cluster" {
  description = "Name of the compute cluster to place the VM in (its root resource pool). Provide this OR resource_pool."
  type        = string
  default     = ""

  validation {
    condition     = var.cluster != "" || var.resource_pool != ""
    error_message = "Provide cluster or resource_pool."
  }
}

variable "resource_pool" {
  description = "Name/path of the resource pool to place the VM in. Takes precedence over cluster."
  type        = string
  default     = ""
}

variable "network" {
  description = "Name of the port group / network the VM's NIC joins (DHCP is assumed; the parent dials the VM's guest IP :9443 in-network)"
  type        = string
}

variable "template" {
  description = "Name of the VM template to clone. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (e.g. imported from ubuntu-24.04-server-cloudimg-amd64.ova) — a plain installer-built template ignores the guestinfo userdata and Traefik never starts."
  type        = string
}

variable "folder" {
  description = "VM folder to place the VM in. Empty = the datacenter root."
  type        = string
  default     = ""
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

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk size in GB. Grown to at least the template's disk (vSphere can't shrink on clone)."
  type        = number
  default     = 20
}

variable "extra_labels" {
  description = "Extra Traefik labels merged into the VM's own `guestinfo.traefik` extraConfig entry (on top of the dashboard self-registration labels, when enabled)"
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

variable "vsphere_provider" {
  description = <<-EOT
    Traefik Hub vsphere provider configuration (hub.providers.vsphere). The provider is
    vCENTER-NATIVE: it reads service membership from vCenter TAGS and takes its routing
    intent from a base configuration, rather than from per-VM labels.

      service_name_category_key  the vCenter tag CATEGORY whose tags name services. A VM
                                 tagged `vmrr` in that category is a server of the `vmrr`
                                 service; with a MULTIPLE-cardinality category a VM can
                                 carry several tags and back several services (that is how
                                 one fleet is published under three LB strategies).
      config_endpoint            URL the gateway polls for the base config (GitOps), OR
      filename                   a path to it on the gateway host. Exactly one.

    Discovery goes through vCenter's vAPI tagging service, which a standalone ESXi host
    does not serve — so this provider requires vCenter, by design.

    vSphere has no ambient identity, so endpoint + username are required when enabled; the
    password rides the separate sensitive var.vsphere_password. endpoint may be a bare
    vCenter host (the provider applies https + /sdk); insecure_skip_verify defaults on
    (self-signed vCenter certs are the norm); datacenter empty = all datacenters.
  EOT
  type = object({
    enabled                     = optional(bool, true)
    endpoint                    = optional(string, "")
    username                    = optional(string, "")
    insecure_skip_verify        = optional(bool, true)
    datacenter                  = optional(string, "")
    ip_mode                     = optional(string, "private")
    service_name_category_key   = optional(string, "TraefikServiceName")
    config_endpoint             = optional(string, "")
    config_insecure_skip_verify = optional(bool, false)
    filename                    = optional(string, "")
    refresh_seconds             = optional(number, null)
  })
  default = {}

  validation {
    condition     = !var.vsphere_provider.enabled || (var.vsphere_provider.endpoint != "" && var.vsphere_provider.username != "")
    error_message = "vsphere_provider.endpoint and vsphere_provider.username are required when the provider is enabled (vSphere has no ambient identity)."
  }

  validation {
    condition     = !var.vsphere_provider.enabled || ((var.vsphere_provider.config_endpoint == "") != (var.vsphere_provider.filename == ""))
    error_message = "Set exactly one of vsphere_provider.config_endpoint (GitOps URL) or vsphere_provider.filename (path on the gateway) — the provider takes its routers/services from one base configuration."
  }
}

variable "vsphere_password" {
  description = "vCenter password the gateway's vsphere provider authenticates with. Point it at a READ-ONLY vCenter role — discovery only lists VMs. Optional, because a child on vSphere need not discover BY vSphere: the docker-provider leg runs the same module with vsphere_provider.enabled = false and has no business carrying a vCenter secret."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = !var.vsphere_provider.enabled || var.vsphere_password != ""
    error_message = "vsphere_password is required when vsphere_provider.enabled (vSphere has no ambient identity — no instance profile, managed identity or IMDS to fall back on)."
  }
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
  description = "Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. vsphere)"
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
  description = "Custom plugins to use for the deployment"
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

variable "enable_dashboard_discovery" {
  description = "Self-register the Traefik VM via its own `guestinfo.traefik` entry (traefik.enable + dashboard router/service) so its OWN vsphere provider discovers the dashboard as dashboard@vsphere. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the VM isn't self-discovered at all."
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  type        = string
  description = "Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt."
  default     = ""
}
