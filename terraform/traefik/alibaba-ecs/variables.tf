# =============================================================================
# Alibaba-ECS-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/oci-vm (same names, so demo code reads identically across platforms).
# =============================================================================

variable "vm_name" {
  description = "Base name for the Traefik instance and its RAM/network resources"
  type        = string
  default     = "traefik"
}

variable "instance_type" {
  description = "ECS instance type (default: 2 vCPU / 4 GB economy)"
  type        = string
  default     = "ecs.e-c1m2.large"
}

variable "system_disk_category" {
  description = "System disk category. ESSD Entry pairs with the economy (e-series) default instance type; switch to cloud_essd for g/c families."
  type        = string
  default     = "cloud_essd_entry"
}

variable "system_disk_size" {
  description = "System disk size (GB)"
  type        = number
  default     = 40
}

variable "image_id" {
  description = "Boot image ID. Empty = latest public Ubuntu 24.04 x64 image."
  type        = string
  default     = ""
}

variable "vswitch_id" {
  description = "ID of the existing vswitch the instance joins (the parent dials the instance's private IP :9443 in-VPC, e.g. compute/alibaba/vpc's vswitch_id)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the module-created security group is created in. Only required when enable_security_group = true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_security_group || var.vpc_id != ""
    error_message = "vpc_id must be provided when enable_security_group is true"
  }
}

variable "security_group_ids" {
  description = "Existing security group IDs to attach to the instance (Alibaba requires at least one unless enable_security_group is on, e.g. compute/alibaba/vpc's security_group_ids)"
  type        = list(string)
  default     = []
}

variable "enable_security_group" {
  description = "Create a security group opening security_group_ingress_ports to the instance from security_group_source_cidr (mirrors traefik/oci-vm's enable_nsg). Off by default — compute/alibaba/vpc's group already opens the demo ports. Requires vpc_id."
  type        = bool
  default     = false
}

variable "security_group_ingress_ports" {
  description = "TCP ports the module-created security group opens on the instance. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials."
  type        = list(number)
  default     = [80, 443, 8080, 9443]
}

variable "security_group_source_cidr" {
  description = "Source CIDR the module-created security group allows. Default covers RFC1918 VPCs (compute/alibaba/vpc's VPC is 10.0.0.0/16)."
  type        = string
  default     = "10.0.0.0/8"
}

variable "enable_public_ip" {
  description = "Allocate a public IP to the instance (Alibaba grants one when outbound bandwidth > 0). Off by default — the parent dials the private IP (same VPC); without it, docker pulls need a NAT gateway on the vswitch."
  type        = bool
  default     = false
}

variable "enable_ram_role" {
  description = "Create an instance RAM role (trusted by ecs.aliyuncs.com) + read-only ecs:Describe* policy and attach it — the alibabaECS provider's keyless credential via the default chain (env -> profile -> RAM role metadata). RAM names are account-global (derived from vm_name); disable when the demo already created them."
  type        = bool
  default     = true
}

variable "extra_tags" {
  description = "Extra tags to apply to the instance"
  type        = map(string)
  default     = {}
}

variable "extra_files" {
  type = list(object({
    path    = string
    content = string
  }))
  description = "Extra files to write to the instance at cloud-init time"
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

variable "alibabaecs_provider" {
  description = "Traefik Hub alibabaECS provider configuration (hub.providers.alibabaECS). region_id defaults to the instance's own region (from the alicloud provider); endpoint defaults to the regional one. No access keys: empty credentials make the provider fall through the default chain (env -> profile -> instance RAM role via metadata — see enable_ram_role)."
  type = object({
    enabled                       = optional(bool, true)
    region_id                     = optional(string, "")
    endpoint                      = optional(string, "")
    ip_mode                       = optional(string, "private")
    exposed_by_default            = optional(bool, false)
    default_rule                  = optional(string, "")
    constraints                   = optional(string, "")
    refresh_seconds               = optional(number, null)
    security_group_port_discovery = optional(bool, false)
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
  description = "Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. alibabaECS)"
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
  description = "Self-register the Traefik instance via tags (traefik.enable + dashboard router/service) so its OWN alibabaECS provider discovers the dashboard as dashboard@alibabaecs. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the instance isn't self-discovered at all."
  type        = bool
  default     = true
}

variable "private_ip" {
  type        = string
  description = "Fixed private IP for the gateway instance. Must sit in vswitch_id's CIDR outside Alibaba's reserved first-3/last-1 hosts. Pinning it makes the hub's uplink dial address plan-known (no two-pass PENDING apply) and stable across instance recreation (the hub never dials a stale IP). Empty = DHCP."
  default     = ""
}
