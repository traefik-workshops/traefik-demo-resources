# =============================================================================
# ACI-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/ecs (same names, so demo code reads identically across platforms).
# =============================================================================

variable "name" {
  description = "Name of the Traefik container group"
  type        = string
  default     = "traefik"
}

variable "resource_group_name" {
  description = "Resource group the container group is created in (also the aci provider's default discovery scope)"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
  default     = "eastus"
}

variable "subnet_id" {
  description = "ID of the existing subnet the container group joins. MUST be delegated to Microsoft.ContainerInstance (compute/azure/vnet's aci_subnet_id already is). The parent dials the group's private IP :9443 in-vnet."
  type        = string
}

variable "container_cpu" {
  description = "vCPU allocation for the Traefik container"
  type        = string
  default     = "1.0"
}

variable "container_memory" {
  description = "Memory allocation (GB) for the Traefik container"
  type        = string
  default     = "2.0"
}

variable "enable_reader_role" {
  description = "Assign the Reader role on the provider's resource group to the group's system-assigned identity (requires the caller to hold role-assignment rights, e.g. Owner/User Access Administrator)."
  type        = bool
  default     = true
}

variable "extra_tags" {
  description = "Extra tags to apply to the container group"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

variable "aci_provider" {
  description = "Traefik Hub aci provider configuration (hub.providers.aci). subscription_id defaults to the caller's (data.azurerm_client_config); resource_group defaults to resource_group_name. No client credentials: DefaultAzureCredential resolves the group's system-assigned managed identity. Without port_discovery the provider falls back to the container group's lowest declared exposed port."
  type = object({
    enabled            = optional(bool, true)
    subscription_id    = optional(string, "")
    resource_group     = optional(string, "")
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
  description = "Enable Traefik Hub Preview features"
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
  description = "Self-register the Traefik container group via tags (traefik.enable + dashboard router/service) so its OWN aci provider discovers the dashboard as dashboard@aci. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the group isn't self-discovered at all."
  type        = bool
  default     = true
}
