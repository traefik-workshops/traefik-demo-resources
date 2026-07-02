# =============================================================================
# IBM-VPC-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/alibaba-ecs (same names, so demo code reads identically across
# platforms).
# =============================================================================

variable "vm_name" {
  description = "Base name for the Traefik instance and its network resources"
  type        = string
  default     = "traefik"
}

variable "instance_profile" {
  description = "VSI profile (default: 2 vCPU / 4 GB — the smallest VPC gen2 compute profile)"
  type        = string
  default     = "cx2-2x4"
}

variable "image_id" {
  description = "Boot image ID. Empty = latest stock Ubuntu 24.04 amd64 image."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "ID of the existing subnet the instance joins (the parent dials the instance's private IP :9443 in-VPC, e.g. compute/ibm/vpc's subnet_id). The zone, VPC and default provider region derive from it."
  type        = string
}

variable "security_group_ids" {
  description = "Existing security group IDs to attach to the instance (e.g. compute/ibm/vpc's security_group_ids). IBM security groups deny both directions by default — the attached groups must allow the demo ports in and image pulls out."
  type        = list(string)
  default     = []
}

variable "enable_security_group" {
  description = "Create a security group opening security_group_ingress_ports to the instance from security_group_source_cidr, plus allow-all egress (mirrors traefik/alibaba-ecs's enable_security_group). Off by default — compute/ibm/vpc's group already opens the demo ports."
  type        = bool
  default     = false
}

variable "security_group_ingress_ports" {
  description = "TCP ports the module-created security group opens on the instance. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials."
  type        = list(number)
  default     = [80, 443, 8080, 9443]
}

variable "security_group_source_cidr" {
  description = "Source CIDR the module-created security group allows. Default covers RFC1918 VPCs (compute/ibm/vpc's VPC is 10.0.0.0/16)."
  type        = string
  default     = "10.0.0.0/8"
}

variable "enable_floating_ip" {
  description = "Attach a floating IP to the instance (inbound access only — public entrypoints / dashboard). Off by default: the parent dials the private IP (same VPC), and image pulls ride the subnet's public gateway."
  type        = bool
  default     = false
}

variable "ssh_key_ids" {
  description = "IBM Cloud SSH key IDs to inject (debugging convenience)"
  type        = list(string)
  default     = []
}

variable "resource_group_id" {
  description = "Resource group ID the instance and network resources land in. Empty = the account's default resource group."
  type        = string
  default     = ""
}

variable "extra_tags" {
  description = "Extra user tags (flat strings) to apply to the instance"
  type        = list(string)
  default     = []
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

variable "ibmcloud_api_key" {
  description = "IBM Cloud IAM API key the ibmVPC provider authenticates with (--hub.providers.ibmVPC.apiKey). REQUIRED when the provider is enabled: IBM VSIs expose no ambient instance identity the provider can consume — there is no keyless path like EC2 instance profiles or Alibaba RAM roles. Scope the key to VPC + Global Search reader roles."
  type        = string
  default     = ""
  sensitive   = true
}

variable "base_config_content" {
  description = "The ibmVPC provider's BASE CONFIGURATION file content (YAML routers/services/middlewares). REQUIRED when the provider is enabled — instances carry only a '<serviceNameTagKey>:<service>' tag, and the provider fills each service's servers with the tagged instances' IPs. Shipped to the VM at base_config_path via cloud-init and hot-reloaded on change (fsnotify)."
  type        = string
  default     = ""
}

variable "base_config_path" {
  description = "Path on the VM the base configuration file is written to and the provider reads it from (--hub.providers.ibmVPC.filename). Keep it under /data (mounted into the preview-mode container) and OUT of /etc/traefik-hub/dynamic (the file provider watches that directory and would double-load the routers)."
  type        = string
  default     = "/data/traefik-hub/ibmvpc.yaml"
}

variable "ibmvpc_provider" {
  description = "Traefik Hub ibmVPC provider configuration (hub.providers.ibmVPC). region and vpc_id default to the joined subnet's region/VPC; endpoint/search_endpoint default to the regional/global ones; service_name_tag_key defaults to the provider's own default (traefik-service-name); poll_interval is a duration string (provider default 30s). ipv6 ip_mode yields nothing on VPC. Credentials come from var.ibmcloud_api_key; the base configuration file from var.base_config_content."
  type = object({
    enabled              = optional(bool, true)
    region               = optional(string, "")
    endpoint             = optional(string, "")
    search_endpoint      = optional(string, "")
    vpc_id               = optional(string, "")
    service_name_tag_key = optional(string, "")
    ip_mode              = optional(string, "private")
    poll_interval        = optional(string, "")
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
  description = "Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. ibmVPC)"
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
