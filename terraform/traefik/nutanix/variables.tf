# =============================================================================
# Nutanix VM-specific Variables
# =============================================================================
# Shared Traefik variables are defined in shared.tf.
# This file contains only Nutanix platform-specific variables.
# =============================================================================

variable "vm_name" {
  description = "Name of the VM"
  type        = string
}

variable "cluster_id" {
  description = "UUID of the Nutanix Cluster"
  type        = string
}

variable "subnet_uuid" {
  description = "UUID of the Subnet"
  type        = string
}

variable "image_id" {
  description = "UUID of the Image to use"
  type        = string
}

variable "arch" {
  description = "Architecture of the VM"
  type        = string
  default     = "amd64"
}

variable "vm_num_vcpus_per_socket" {
  description = "Number of vCPUs per socket"
  type        = number
  default     = 1
}

variable "vm_num_sockets" {
  description = "Number of sockets"
  type        = number
  default     = 1
}

variable "vm_memory_mib" {
  description = "Memory size in MiB"
  type        = number
  default     = 2048
}

variable "vm_disk_size_mib" {
  description = "Disk size in MiB"
  type        = number
  default     = 20480 # 20 GB
}

variable "vm_static_ip" {
  description = "Optional static IP for the VM's NIC (inside subnet CIDR). Empty = DHCP."
  type        = string
  default     = ""
}

variable "vip" {
  description = "Virtual IP for Keepalived"
  type        = string
  default     = ""
}

variable "keepalived_priority" {
  description = "Priority for Keepalived VRRP (higher wins)"
  type        = number
  default     = 100
}

variable "network_interface" {
  description = "Network interface name for Keepalived VRRP"
  type        = string
  default     = "ens3"
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
  description = "Number of replicas (Nutanix VMs)"
  type        = number
  default     = 1
}

# Versions & Images
variable "traefik_chart_version" {
  description = "Traefik Helm chart version"
  type        = string
  # Chart 40.3.0 publishes hub-max v3.20.4 — the multicluster-verified pairing (matches traefik/k8s).
  default = "40.3.0"
}

variable "traefik_tag" {
  description = "Traefik OSS version tag"
  type        = string
  default     = "v3.7.4"
}

variable "traefik_hub_tag" {
  description = "Traefik Hub version tag"
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

# Typed `any`, matching traefik/shared and traefik/vsphere-vm. The old
# map(object({ port, protocol })) shape could not express a Hub multicluster UPLINK
# entrypoint — { port = 9443, uplink = true, expose = { default = true },
# http = { tls = { enabled = true } } } — so a Nutanix child had to declare its uplink
# through custom_arguments instead, and the flag form that fits on one line
# (--hub.uplinkEntryPoints.X.asDefault=true) makes EVERY router uplink by default.
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

variable "extra_files" {
  type = list(object({
    path    = string
    content = string
  }))
  description = "Extra files to write to the VM at cloud-init time"
  default     = []
}

# =============================================================================
# Docker-provider leg (see the wiring comment in main.tf)
# =============================================================================

variable "mount_docker_socket" {
  type        = bool
  description = "Bind /var/run/docker.sock into the Traefik container so its docker provider can reach the local daemon. Root-equivalent access to the host, so leave it off for any gateway that is not the docker-provider leg. Takes effect only with enable_preview_mode — in binary mode there is no container to bind it into."
  default     = false
}

variable "extra_runcmd" {
  type        = list(string)
  description = "Extra shell blocks appended to cloud-init runcmd, after Docker is installed and before traefik-hub starts. Used to run workload containers on the gateway VM itself (the docker-provider leg), which is required rather than thrifty: --providers.docker reads a UNIX socket, and no remote gateway can dial one. Takes effect only with enable_preview_mode — Docker is installed on that path alone."
  default     = []
}

variable "ssh_public_key" {
  type        = string
  description = "Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt."
  default     = ""
}

variable "enable_dashboard_discovery" {
  description = "Stamp this gateway VM with TraefikServiceName=traefik so its OWN nutanixprismcentral provider discovers it and can publish the dashboard as traefik@nutanixprismcentral. Disable when the dashboard is advertised another way (e.g. a file-rule uplink to a multicluster parent) so the VM is not self-discovered at all — see main.tf for what leaving it on costs."
  type        = bool
  default     = true
}

variable "file_provider_path" {
  description = "Path where the file provider config is mounted"
  type        = string
  default     = "/etc/traefik-hub/dynamic/"
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
variable "enable_dashboard" {
  description = "Enable Traefik dashboard"
  type        = bool
  default     = true
}

variable "dashboard_insecure" {
  description = "Enable insecure dashboard access (no auth)"
  type        = bool
  default     = false
}

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

# Entry Points
variable "entry_points" {
  description = "Entry points configuration"
  type = map(object({
    address = string
  }))
  default = {
    web       = { address = ":80" }
    websecure = { address = ":443" }
    traefik   = { address = ":8080" }
  }
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

# The first-party Hub provider (--hub.providers.nutanixPrismCentral.*), compiled into the
# Hub image. It reads ONE thing off Prism Central: the value of the category whose key is
# service_name_category_key, per powered-on VM. Everything else about the resulting service
# — port, scheme, health check, strategy, weighted composition — comes from the `filename`
# base config, NOT from Nutanix.
#
# `endpoint` MUST carry a scheme (provider.go Init() rejects a bare host:port), and
# api_key XOR username+password: configuring both is a hard startup error, not a preference.
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
    filename             = optional(string, "")

    # Scope discovery to these VPCs. WITHOUT it the gateway adopts every powered-on VM in
    # the WHOLE of Prism Central that carries the category — which on a shared POC pod is
    # cross-tenant. The provider resolves it to a subnet allow-list and then only considers
    # NICs in those subnets (discovery.go fetchAllowedSubnets/extractIP).
    allowed_vpcs = optional(list(object({ uuid = string })), [])

    # Which category key names the service. Defaults to the provider's own default; override
    # only when an existing Prism Central taxonomy already owns that key.
    service_name_category_key = optional(string, "TraefikServiceName")
  })
  default = {
    enabled = false
  }
  sensitive = true
}

variable "dns_traefiker" {
  description = "DNS Traefiker configuration for automatic domain registration"
  type = object({
    enabled                   = optional(bool, false)
    version                   = optional(string, "v1.0.4")
    chart                     = optional(string, "")
    unique_domain             = optional(bool, false)
    domain                    = optional(string, "")
    enable_airlines_subdomain = optional(bool, false)
    ip_override               = optional(string, "")
    proxied                   = optional(bool, false)
  })
  default = {
    enabled = false
  }
}
