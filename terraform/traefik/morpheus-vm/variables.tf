# =============================================================================
# Morpheus-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/ec2, traefik/azure-vm and traefik/vsphere-vm (same names, so demo
# code reads identically across platforms).
# =============================================================================

variable "cloud" {
  description = "Name of the Morpheus cloud (e.g. the MVM/HVM cloud registered on the appliance) the instance is provisioned into"
  type        = string
}

variable "group" {
  description = "Name of the Morpheus group the instance belongs to"
  type        = string
}

variable "instance_type" {
  description = "Name of the Morpheus instance type to provision from (e.g. \"Ubuntu\"). Must boot a cloud-init-enabled Linux image — the Morpheus agent (installed via cloud-init) runs the Traefik bootstrap."
  type        = string
  default     = "Ubuntu"
}

variable "instance_layout" {
  description = "Name of the instance layout under instance_type (e.g. \"Single KVM VM\")"
  type        = string
}

variable "instance_layout_version" {
  description = "Version of the instance layout (e.g. \"24.04\") — disambiguates layouts sharing a name. Empty = match by name alone."
  type        = string
  default     = ""
}

variable "plan" {
  description = "Name of the service plan — the plan IS the VM shape on Morpheus (no cpu/memory knobs here); pick one that fits a gateway (e.g. \"2 CPU, 4GB Memory\")"
  type        = string
}

variable "plan_provision_type" {
  description = "Provision type CODE the plan is looked up under (the hpe_morpheus_service_plan data source filters by provision_type_code; \"kvm\" for MVM / HPE VM Essentials clouds — the gomorpheus-era value here was the NAME \"KVM\"). Empty = match the plan by name alone."
  type        = string
  default     = "kvm"
}

variable "resource_pool_name" {
  description = "Name of the resource pool (the MVM/HVM cluster) to provision the instance to"
  type        = string
}

variable "network" {
  description = "Name of the Morpheus network the instance NIC joins (DHCP is assumed; the parent dials the instance's primary IP :9443 in-network). Empty = the layout's default network selection."
  type        = string
  default     = ""
}

variable "network_interface_type_id" {
  description = "Morpheus network interface TYPE ID for the NIC (required when network is set)"
  type        = number
  default     = null
}

variable "root_volume" {
  type = object({
    size         = number
    datastore_id = number
    storage_type = optional(number, 1)
    name         = optional(string, "root")
  })
  description = "Optional explicit root volume {size (GB), datastore_id, storage_type, name}. null = the layout/plan defaults."
  default     = null
}

# tflint-ignore: terraform_unused_declarations # deliberate compat shim: validated-empty (HPE/hpe has no labels attribute)
variable "morpheus_labels" {
  description = "MUST STAY EMPTY: the HPE/hpe provider's hpe_morpheus_instance exposes NO labels attribute (checked at v1.5.0; gomorpheus's morpheus_mvm_instance did), so Morpheus labels can't be applied from terraform anymore. The variable is kept (and validated empty) so existing callers passing [] keep working; set labels in the appliance instead."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.morpheus_labels) == 0
    error_message = "morpheus_labels cannot be applied: hpe_morpheus_instance (HPE/hpe v1.5.0) has no labels attribute — the gomorpheus labels feature has no HPE equivalent yet. Leave empty and set labels via the appliance."
  }
}

variable "vm_name" {
  description = "Base name for the Traefik instance (also the prefix of the bootstrap task/workflow names — unique per appliance)"
  type        = string
  default     = "traefik"
}

variable "extra_labels" {
  description = "Extra Traefik labels merged into the instance's own `traefik.*` tags (on top of the dashboard self-registration labels, when enabled)"
  type        = map(string)
  default     = {}
}

variable "extra_files" {
  type = list(object({
    path    = string
    content = string
  }))
  description = "Extra files to write to the instance at bootstrap time"
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

variable "morpheus_provider" {
  description = "Traefik Hub morpheus provider configuration (hub.providers.morpheus). Morpheus has no ambient identity, so credentials are explicit: an API access token (var.morpheus_access_token, PREFERRED) or username here + var.morpheus_password — the gateway's Init enforces exactly one method. endpoint must be the full appliance URL INCLUDING the scheme (Init rejects a bare host); insecure_skip_verify defaults on (self-signed appliance certs are the norm); ipMode private/public both resolve to an instance's primary connection address on-prem."
  type = object({
    enabled              = optional(bool, true)
    endpoint             = optional(string, "")
    username             = optional(string, "")
    insecure_skip_verify = optional(bool, true)
    ip_mode              = optional(string, "private")
    exposed_by_default   = optional(bool, false)
    default_rule         = optional(string, "")
    constraints          = optional(string, "")
    refresh_seconds      = optional(number, null)
  })
  default = {}

  validation {
    condition     = !var.morpheus_provider.enabled || can(regex("^https?://", var.morpheus_provider.endpoint))
    error_message = "morpheus_provider.endpoint is required when the provider is enabled and must be a full URL including the scheme (the gateway's Init rejects a bare host)."
  }
}

variable "morpheus_access_token" {
  description = "Morpheus API access token the gateway's morpheus provider authenticates with (PREFERRED — mint it for a read-only user; discovery only lists instances). Empty = username/password auth via morpheus_provider.username + morpheus_password."
  type        = string
  sensitive   = true
  default     = ""
}

variable "morpheus_password" {
  description = "Morpheus password for morpheus_provider.username (the username/password alternative to morpheus_access_token). Point it at a READ-ONLY role — the credential lands in the instance's bootstrap task and unit file."
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
  description = "Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. morpheus)"
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
  description = "Self-register the Traefik instance via its own `traefik.*` tags (traefik.enable + dashboard router/service) so its OWN morpheus provider discovers the dashboard as dashboard@morpheus. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the instance isn't self-discovered at all."
  type        = bool
  default     = true
}
