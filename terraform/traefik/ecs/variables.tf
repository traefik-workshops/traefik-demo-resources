# =============================================================================
# ECS-specific Variables
# =============================================================================
# Shared Traefik variables are defined in shared.tf.
# This file contains only ECS platform-specific variables.
# =============================================================================

variable "create_vpc" {
  description = "Create VPC if vpc_id is not provided"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID for ECS resources"
  type        = string
  default     = ""

  validation {
    condition     = var.create_vpc || var.vpc_id != ""
    error_message = "vpc_id must be provided if create_vpc is false"
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS tasks"
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.subnet_ids) > 0
    error_message = "subnet_ids must be provided if create_vpc is false"
  }
}

variable "security_group_ids" {
  description = "List of security group IDs for ECS tasks"
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.security_group_ids) > 0
    error_message = "security_group_ids must be provided if create_vpc is false"
  }
}

variable "extra_labels" {
  description = "Extra labels to apply to the ECS task"
  type        = map(string)
  default     = {}
}

variable "task_role_arn" {
  description = "IAM role ARN the Traefik task assumes (the task role) — e.g. so the in-task ECS provider can call the AWS ECS API. Empty = no task role."
  type        = string
  default     = ""
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

variable "replica_count" {
  description = "Number of replicas (ECS tasks)"
  type        = number
  default     = 1
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

variable "nlb_port" {
  description = "If set, front the Traefik Fargate task with an NLB on this port and make it the task's exposed/targeted container port (e.g. 9443 for a Hub multicluster uplink the parent dials). Null = no NLB, port stays 80."
  type        = number
  default     = null
}

variable "nlb_internal" {
  description = "Make the NLB internal (private IPs only) instead of internet-facing — for a parent that dials this spoke privately within a shared VPC. Requires private (NAT-routed) subnet_ids + assign_public_ip = false."
  type        = bool
  default     = false
}

variable "assign_public_ip" {
  description = "Assign a public IP to the Fargate task (needed for image pull when tasks run in public subnets)."
  type        = bool
  default     = true
}

variable "colocated_backend_image" {
  description = "If set, run this image as an essential sidecar in the Traefik task (reachable on localhost) — e.g. a whoami the file-provider config advertises over the uplink. Empty = no sidecar."
  type        = string
  default     = ""
}

variable "colocated_backend_port" {
  description = "Container port the colocated backend listens on (reached via localhost from Traefik)."
  type        = number
  default     = 80
}

variable "extra_ingress_ports" {
  description = "Additional TCP ports to open on the created VPC's security group (passed to compute/aws/ecs). Set to [9443] when fronting a Hub uplink entrypoint with an NLB."
  type        = list(number)
  default     = []
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

# Licensing & DNS
variable "traefik_hub_token" {
  description = "Traefik Hub license token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_dns" {
  description = "Cloudflare DNS configuration for certificate resolver"
  type = object({
    enabled           = optional(bool, false)
    domain            = optional(string, "")
    api_token         = optional(string, "")
    extra_san_domains = optional(list(string), [])
  })
  default = {
    enabled           = false
    domain            = ""
    api_token         = ""
    extra_san_domains = []
  }
  sensitive = true
}

variable "is_staging_letsencrypt" {
  description = "Use Let's Encrypt staging environment"
  type        = bool
  default     = false
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
  description = "Self-register the Traefik task via tags (traefik.enable + dashboard router/service) so its OWN ECS provider discovers the dashboard as dashboard@ecs. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the task isn't self-discovered at all."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

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

variable "nutanix_provider" {
  description = "Nutanix Prism Central provider configuration for VM discovery"
  type = object({
    enabled              = optional(bool, false)
    endpoint             = optional(string, "")
    username             = optional(string, "")
    password             = optional(string, "")
    api_key              = optional(string, "")
    insecure_skip_verify = optional(bool, false)
    poll_interval        = optional(string, "30s")
    poll_timeout         = optional(string, "5s")
  })
  default = {
    enabled = false
  }
  sensitive = true
}

variable "otlp_gate_address" {
  description = <<-EOD
    OTLP collector base URL (e.g. https://collector.example.com). When set, a non-essential
    sidecar with `dependsOn: COMPLETE` holds this gateway's container until that endpoint
    ACCEPTS an OTLP write. Empty disables the gate.

    Set it whenever this gateway exports telemetry. An exporter whose FIRST export goes
    into a void does not reliably recover: the lookup lands before the collector's DNS
    record exists, NXDOMAIN is negatively cached for the zone's SOA MINIMUM (1800s on
    traefik.ai), and every retry inside that window asks the cache rather than the
    authority. Measured on aws-unified-ingress 2026-08-11 — task up 14:50:29, record
    published 15:13, still resolving `no such host` at 15:29:09, 39 minutes dark while
    every act passed. Whether a run recovers is a race, and a green service map without
    this gate is luck rather than proof.

    MUST BE PLAN-KNOWN. Build it from the domain; never read it off an attribute of the
    hub. This gate adds no terraform edge — it renders into the task definition, and the
    NLB the hub consumes as its uplink address exists whether or not any container starts
    — but a COMPUTED address puts a real edge back into the graph and deadlocks the apply
    with no cycle error, which neither `validate` nor `graph` will catch.
  EOD
  type        = string
  default     = ""
}
