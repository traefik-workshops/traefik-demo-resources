# =============================================================================
# Alibaba-ECI-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/aci and traefik/oci-ci (same names, so demo code reads identically
# across platforms).
# =============================================================================

variable "name" {
  description = "Name of the Traefik container group (also the base name for its RAM resources)"
  type        = string
  default     = "traefik"
}

variable "vswitch_id" {
  description = "ID of the existing vswitch the container group joins (the parent dials the group's private IP :9443 in-VPC, e.g. compute/alibaba/vpc's vswitch_id)"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID attached to the container group (required by ECI, e.g. compute/alibaba/vpc's security_group_id — its extra_ingress_ports must cover the :9443 uplink)"
  type        = string
}

variable "container_cpu" {
  description = "vCPUs for the Traefik container group"
  type        = number
  default     = 1
}

variable "container_memory" {
  description = "Memory (GB) for the Traefik container group"
  type        = number
  default     = 4
}

variable "extra_tags" {
  description = "Extra tags to apply to the container group"
  type        = map(string)
  default     = {}
}

variable "enable_ram_role" {
  description = "Create a RAM role (trusted by ecs.aliyuncs.com — the trust ECI's metadata mechanism requires) + read-only eci:Describe* policy and bind it to the group — the alibabaECI provider's keyless credential via the default chain (env -> profile -> RAM role metadata). RAM names are account-global (derived from name); disable when the demo already created them, and pass access keys instead."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Alibaba credentials (access-key fallback)
# -----------------------------------------------------------------------------

variable "access_key_id" {
  description = "Alibaba Cloud access key ID the alibabaECI provider authenticates with — the fallback when enable_ram_role is off (e.g. no RAM rights). Empty = the default credential chain (the RAM role)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "access_key_secret" {
  description = "Alibaba Cloud access key secret paired with access_key_id"
  type        = string
  default     = ""
  sensitive   = true
}

variable "security_token" {
  description = "Alibaba Cloud STS security token — only for temporary (STS) access keys"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

variable "alibabaeci_provider" {
  description = "Traefik Hub alibabaECI provider configuration (hub.providers.alibabaECI). region_id defaults to the group's own region (from the alicloud provider); endpoint defaults to the regional one. No access keys here: empty credentials make the provider fall through the default chain (env -> profile -> RAM role via metadata — see enable_ram_role); the access_key_* variables are the explicit fallback. Without port_discovery the provider needs explicit port tags; with it, it falls back to the group's lowest declared container port."
  type = object({
    enabled            = optional(bool, true)
    region_id          = optional(string, "")
    endpoint           = optional(string, "")
    ip_mode            = optional(string, "private")
    exposed_by_default = optional(bool, false)
    default_rule       = optional(string, "")
    constraints        = optional(string, "")
    refresh_seconds    = optional(number, null)
    port_discovery     = optional(bool, false)
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
  description = "Enable Traefik Hub Preview features (required for provider builds not yet in a Hub release, e.g. alibabaECI)"
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
  description = "Custom ports configuration. Typed `any` so it can carry a full Helm `ports.<name>` shape — e.g. a Hub multicluster uplink entrypoint { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } }."
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
  default     = "/etc/traefik/dynamic"
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
  description = "Self-register the Traefik container group via tags (traefik.enable + dashboard router/service) so its OWN alibabaECI provider discovers the dashboard as dashboard@alibabaeci. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the group isn't self-discovered at all."
  type        = bool
  default     = true
}
