# =============================================================================
# OCI-CI-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/aci (same names, so demo code reads identically across platforms).
# =============================================================================

variable "name" {
  description = "Name of the Traefik container instance"
  type        = string
  default     = "traefik"
}

variable "compartment_id" {
  description = "OCID of the compartment the container instance is created in (also the ociContainerInstances provider's default discovery scope)"
  type        = string
}

variable "tenancy_id" {
  description = "OCID of the tenancy — where the resource-principal dynamic group is created (dynamic groups are tenancy-level). Required when enable_resource_principal = true."
  type        = string
  default     = ""
}

variable "availability_domain" {
  description = "Availability domain the container instance is placed in. Empty = the compartment's first AD (same pick as compute/oracle/oke)."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "OCID of the existing subnet the container instance VNIC joins (the parent dials the instance's private IP :9443 in-VCN, e.g. compute/oracle/oke's nodes_subnet_id)"
  type        = string
}

variable "nsg_ids" {
  description = "Network security group OCIDs to attach to the container instance VNIC"
  type        = list(string)
  default     = []
}

variable "shape" {
  description = "Container instance shape (flex shapes are sized by container_ocpus/container_memory_in_gbs)"
  type        = string
  default     = "CI.Standard.E4.Flex"
}

variable "container_ocpus" {
  description = "OCPUs for the Traefik container instance (1 OCPU = 2 vCPUs on E4.Flex)"
  type        = number
  default     = 1
}

variable "container_memory_in_gbs" {
  description = "Memory (GB) for the Traefik container instance"
  type        = number
  default     = 4
}

variable "extra_tags" {
  description = "Extra freeform tags to apply to the container instance"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# OCI credentials
# -----------------------------------------------------------------------------

variable "enable_resource_principal" {
  description = "Authenticate the ociContainerInstances provider as a RESOURCE principal (useResourcePrincipal=true) — keyless: creates a dynamic group matching the compartment's container instances plus a read-only policy, both named `<name>-resource-principal` (requires tenancy_id and IAM rights; two same-name instantiations collide). Disable to fall back to the oci_config/oci_private_key config-file volume."
  type        = bool
  default     = true
}

variable "oci_config" {
  description = "Content of an ~/.oci style config file — the ociContainerInstances provider's config-file credential, mounted as a CONFIGFILE volume at the directory of ocici_provider.config_file_path. Its key_file MUST point inside that mount (e.g. /etc/oci/key.pem). Required (with oci_private_key) when enable_resource_principal = false; unused otherwise."
  type        = string
  default     = ""
  sensitive   = true
}

variable "oci_private_key" {
  description = "PEM content of the API signing key the oci_config references (mounted as key.pem next to it). Required when enable_resource_principal = false; unused otherwise."
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

variable "ocici_provider" {
  description = "Traefik Hub ociContainerInstances provider configuration (hub.providers.ociContainerInstances). compartment_id defaults to the module's compartment_id. Auth defaults to resource principal (enable_resource_principal); use_instance_principal is an escape hatch that doesn't work on container instances (no IMDS flow) and is mutually exclusive with it. Without nsg_port_discovery the provider falls back to the instance's lowest declared container port."
  type = object({
    enabled                = optional(bool, true)
    compartment_id         = optional(string, "")
    region                 = optional(string, "")
    use_instance_principal = optional(bool, false)
    config_file_path       = optional(string, "/etc/oci/config")
    ip_mode                = optional(string, "private")
    exposed_by_default     = optional(bool, false)
    default_rule           = optional(string, "")
    constraints            = optional(string, "")
    refresh_seconds        = optional(number, null)
    nsg_port_discovery     = optional(bool, false)
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
  description = "Self-register the Traefik container instance via freeform tags (traefik.enable + dashboard router/service) so its OWN ociContainerInstances provider discovers the dashboard as dashboard@ocici. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the instance isn't self-discovered at all."
  type        = bool
  default     = true
}
