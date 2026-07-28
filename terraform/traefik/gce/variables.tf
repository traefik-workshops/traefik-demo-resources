# =============================================================================
# GCE-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/ec2 and traefik/azure-vm (same names, so demo code reads identically
# across platforms).
# =============================================================================

variable "vm_name" {
  description = "Base name for the Traefik VM, its network tag, and its firewall rule"
  type        = string
  default     = "traefik"
}

variable "machine_type" {
  description = "GCE machine type"
  type        = string
  default     = "e2-medium"
}

variable "zone" {
  description = "GCE zone the VM is created in"
  type        = string
  default     = "us-central1-a"
}

variable "vm_image" {
  description = "Boot disk image (family or self link)"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "network" {
  description = "VPC network the VM joins (the parent dials the VM's private IP :9443 in-network). Defaults to the project's default network — the same one compute/gcp/gke clusters sit on (see its `network` output)."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork the VM joins. Empty = let GCP pick the network's subnet in the zone's region (works on auto-mode networks like `default`)."
  type        = string
  default     = ""
}

variable "enable_public_ip" {
  description = "Attach an ephemeral public IP to the VM. Off by default — the parent dials the private IP (same network)."
  type        = bool
  default     = false
}

variable "service_account_id" {
  description = "Account ID for the service account attached to the VM (ADC credential for the gce provider)"
  type        = string
  default     = "traefik-gce"
}

variable "enable_viewer_role" {
  description = "Grant roles/compute.viewer on the provider's project to the VM's service account (requires the caller to hold IAM-grant rights, e.g. Owner/Project IAM Admin)."
  type        = bool
  default     = true
}

variable "enable_firewall" {
  description = "Create a firewall rule opening firewall_ports to the VM from firewall_source_ranges (mirrors compute/azure/vnet's NSG + extra_ingress_ports). Disable when the network already allows it (e.g. default network's default-allow-internal)."
  type        = bool
  default     = true
}

variable "firewall_ports" {
  description = "TCP ports the firewall rule opens on the VM. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials."
  type        = list(number)
  default     = [80, 443, 8080, 9443]
}

variable "firewall_source_ranges" {
  description = "Source CIDR ranges allowed by the firewall rule. Default covers the default network (10.128.0.0/9) and typical GKE node/pod ranges."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "extra_labels" {
  description = "Extra GCE labels to apply to the VM (dotless — constraints only, not traefik.* config)"
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

variable "gce_provider" {
  description = "Traefik Hub gce provider configuration (hub.providers.gce). project_id defaults to the caller's (data.google_client_config); zones empty = all zones. No credentialsFile/credentialsJSON: ADC resolves the VM's attached service account."
  type = object({
    enabled                 = optional(bool, true)
    project_id              = optional(string, "")
    zones                   = optional(list(string), [])
    ip_mode                 = optional(string, "private")
    exposed_by_default      = optional(bool, false)
    default_rule            = optional(string, "")
    constraints             = optional(string, "")
    refresh_seconds         = optional(number, null)
    firewall_port_discovery = optional(bool, false)
  })
  default = {}
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
  description = "Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. gce)"
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
  description = "Self-register the Traefik VM via the `traefik` metadata JSON item (traefik.enable + dashboard router/service) so its OWN gce provider discovers the dashboard as dashboard@gce. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the VM isn't self-discovered at all."
  type        = bool
  default     = true
}

variable "private_ip" {
  type        = string
  description = "Fixed internal IP for the gateway VM (network_interface.network_ip). Must sit in the instance's subnetwork range — on the default auto-mode network that range is region-fixed (us-central1 = 10.128.0.0/20). Pinning it makes the hub's uplink dial address plan-known (no two-pass PENDING apply) and stable across VM recreation. Empty = ephemeral."
  default     = ""
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

variable "ssh_public_key" {
  type        = string
  description = "Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt."
  default     = ""
}
