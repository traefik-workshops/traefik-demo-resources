# =============================================================================
# OCI-VM-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/ec2 (same names, so demo code reads identically across platforms).
# =============================================================================

variable "compartment_id" {
  description = "OCID of the compartment the VM is created in (also the oci provider's default discovery scope and the instance-principal dynamic group's match)"
  type        = string
}

variable "tenancy_id" {
  description = "OCID of the tenancy (root compartment) — the instance-principal dynamic group is tenancy-level and must live here. Required when enable_instance_principal = true."
  type        = string
  default     = ""
}

variable "home_region" {
  description = "Tenancy home region identifier (e.g. us-ashburn-1). OCI IAM writes only succeed against the home region, so the instance-principal dynamic group + policy are created there via the OCI CLI. Required when enable_instance_principal = true."
  type        = string
  default     = ""
}

variable "availability_domain" {
  description = "Availability domain the VM is placed in. Empty = the compartment's first AD (same pick as compute/oracle/oke)."
  type        = string
  default     = ""
}

variable "vm_name" {
  description = "Base name for the Traefik VM and its network resources"
  type        = string
  default     = "traefik"
}

variable "shape" {
  description = "Compute shape (flex shapes are sized by ocpus/memory_in_gbs)"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "ocpus" {
  description = "OCPUs for the VM (1 OCPU = 2 vCPUs on E4.Flex)"
  type        = number
  default     = 1
}

variable "memory_in_gbs" {
  description = "Memory (GB) for the VM"
  type        = number
  default     = 4
}

variable "vm_image_ocid" {
  description = "Boot image OCID. Empty = latest Canonical Ubuntu 24.04 platform image for the shape."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "OCID of the existing subnet the VM VNIC joins (the parent dials the VM's private IP :9443 in-VCN, e.g. compute/oracle/oke's nodes_subnet_id)"
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN the NSG is created in. Only required when enable_nsg = true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_nsg || var.vcn_id != ""
    error_message = "vcn_id must be provided when enable_nsg is true"
  }
}

variable "nsg_ids" {
  description = "Existing network security group OCIDs to attach to the VM VNIC (on top of the optional module-created NSG)"
  type        = list(string)
  default     = []
}

variable "enable_nsg" {
  description = "Create an NSG opening nsg_ingress_ports to the VM from nsg_source_cidr (mirrors traefik/gce's enable_firewall). Off by default — compute/oracle/oke's security list already allows all intra-VCN traffic. Requires vcn_id."
  type        = bool
  default     = false
}

variable "nsg_ingress_ports" {
  description = "TCP ports the module-created NSG opens on the VM. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials."
  type        = list(number)
  default     = [80, 443, 8080, 9443]
}

variable "nsg_source_cidr" {
  description = "Source CIDR the module-created NSG allows. Default covers RFC1918 VCNs (compute/oracle/oke's VCN is 10.0.0.0/16)."
  type        = string
  default     = "10.0.0.0/8"
}

variable "enable_public_ip" {
  description = "Assign a public IP to the VM (requires a public subnet). Off by default — the parent dials the private IP (same VCN)."
  type        = bool
  default     = false
}

variable "enable_instance_principal" {
  description = "Instantiate security/oci-instance-principal (dynamic group matching the compartment's instances + policy) — the oci provider's keyless credential. Requires IAM rights; disable when the demo already created it (the dynamic group/policy names are fixed)."
  type        = bool
  default     = true
}

variable "extra_tags" {
  description = "Extra freeform tags to apply to the VM"
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

variable "oci_provider" {
  description = "Traefik Hub oci provider configuration (hub.providers.oci). compartment_id defaults to the module's compartment_id; region defaults to the instance's own (from IMDS). No configFilePath/profile: useInstancePrincipal resolves the VM's identity keylessly (see enable_instance_principal)."
  type = object({
    enabled                = optional(bool, true)
    compartment_id         = optional(string, "")
    region                 = optional(string, "")
    use_instance_principal = optional(bool, true)
    ip_mode                = optional(string, "private")
    # Base-config file the provider merges discovered IPs into (routers + services
    # with their LB strategy live here). Deliver it via extra_files to a mounted
    # path (e.g. /data/oci-base.yaml).
    filename             = optional(string, "")
    service_name_tag_key = optional(string, "TraefikServiceName")
    refresh_seconds      = optional(number, null)
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
  description = "Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. oci)"
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
  description = "Self-register the Traefik VM via freeform tags (traefik.enable + dashboard router/service) so its OWN oci provider discovers the dashboard as dashboard@oci. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the VM isn't self-discovered at all."
  type        = bool
  default     = true
}

variable "private_ip" {
  type        = string
  description = "Fixed private IP for the gateway VNIC. Must sit in subnet_id's CIDR outside OCI's reserved first-2/last-1 hosts and clear of the OKE node range. Pinning it makes the hub's uplink dial address plan-known (no two-pass PENDING apply) and stable across VM recreation (the hub never dials a stale IP). Empty = DHCP."
  default     = ""
}

variable "ssh_public_key" {
  type        = string
  description = "Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt."
  default     = ""
}
