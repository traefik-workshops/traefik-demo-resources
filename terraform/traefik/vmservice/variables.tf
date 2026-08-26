# =============================================================================
# VM Service-specific Variables
# =============================================================================
# Shared Traefik variables are declared below the platform block, mirroring
# traefik/vsphere-vm (same names, so demo code reads identically across the two
# ways of provisioning a vSphere VM).
# =============================================================================

variable "namespace" {
  description = "vSphere Namespace (a Supervisor namespace) the gateway VirtualMachine is created in. The VirtualMachineClass, the storage class and the image must all be associated with it."
  type        = string
}

variable "class_name" {
  description = "VirtualMachineClass the gateway is sized by (e.g. best-effort-small). `kubectl get virtualmachineclass -n <namespace>` lists the ones bound to the namespace."
  type        = string
}

variable "image_name" {
  description = "VirtualMachineImage the gateway boots from — the name `kubectl get vmi -n <namespace>` shows. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE (ubuntu-*-server-cloudimg-amd64.ova) for the rawCloudConfig bootstrap to take."
  type        = string
}

variable "storage_class" {
  description = "Storage class for the gateway's disk (the namespace's storage policy, e.g. wcp-storage)."
  type        = string
}

variable "network_name" {
  description = "Network the gateway's single interface joins (an NSX segment or VDS port group the namespace is entitled to). Empty = the namespace's default network. The parent dials the VM's guest IP :9443 on it."
  type        = string
  default     = ""
}

variable "api_version" {
  description = "vmoperator.vmware.com API version to write the VirtualMachine with. A Supervisor serves several (`kubectl api-resources | grep vmoperator`); v1alpha3 carries the rawCloudConfig bootstrap this module uses and is served by vSphere 8U2+ and 9."
  type        = string
  default     = "v1alpha3"
}

variable "kubeconfig" {
  description = "Path to the kubeconfig the guest-address wait (local-exec kubectl) should use — the SUPERVISOR kubeconfig, the same one the kubectl provider that creates the VirtualMachine is configured with. Empty = kubectl's ambient config."
  type        = string
  default     = ""
}

variable "kubeconfig_context" {
  description = "Context inside `kubeconfig` to use. Set it so the wait targets a named context instead of whatever the machine-global current-context happens to be at that instant."
  type        = string
  default     = ""
}

variable "ip_wait_timeout" {
  description = "Seconds to wait for the gateway's status.network.primaryIP4 before failing the apply. vm-operator powers the VM on and the namespace network assigns the address within a minute or two on a healthy Supervisor."
  type        = number
  default     = 600
}


variable "vm_name" {
  description = "Base name for the Traefik VM"
  type        = string
  default     = "traefik"
}

variable "extra_files" {
  type = list(object({
    path    = string
    content = string
  }))
  description = "Extra files to write to the VM at cloud-init time"
  default     = []
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

variable "vsphere_provider" {
  description = <<-EOT
    Traefik Hub vsphere provider configuration (hub.providers.vsphere). The provider reads
    each VM's routing intent from the VM's NOTES (config.annotation) as a LINE-FORMAT label
    block — one `traefik.<key>=<value>` per line, the proxmox/hyperv grammar — through one
    SOAP session and one property-collector round trip per refresh. No vAPI, no tags: a
    standalone ESXi host works as well as vCenter. Same-named services across VMs MERGE
    into one load balancer.

      exposed_by_default  false: a VM is published only when its Notes carry
                          traefik.enable=true (gateways, templates and unrelated machines
                          never become backends by accident).
      constraints         a Traefik constraints expression over the VM's labels, e.g.
                          Label(`traefik.tags`, `vm`) — how two gateways sharing one
                          vCenter each pick their own fleet.
      default_rule        the router rule template when a VM declares none ("" = the
                          provider default, Host(`{{ normalize .Name }}`)).
      ip_mode             private | public (both resolve to the guest address VMware Tools
                          reports) | ipv6; per-VM override via the traefik.vsphere.ipmode label.

    vSphere has no ambient identity, so endpoint + username are required when enabled; the
    password rides the separate sensitive var.vsphere_password. endpoint may be a bare
    vCenter/ESXi host (the provider applies https + /sdk); insecure_skip_verify defaults on
    (self-signed vCenter certs are the norm); datacenter empty = all datacenters.
  EOT
  type = object({
    enabled              = optional(bool, true)
    endpoint             = optional(string, "")
    username             = optional(string, "")
    insecure_skip_verify = optional(bool, true)
    datacenter           = optional(string, "")
    ip_mode              = optional(string, "private")
    exposed_by_default   = optional(bool, false)
    constraints          = optional(string, "")
    default_rule         = optional(string, "")
    refresh_seconds      = optional(number, null)
  })
  default = {}

  validation {
    condition     = !var.vsphere_provider.enabled || (var.vsphere_provider.endpoint != "" && var.vsphere_provider.username != "")
    error_message = "vsphere_provider.endpoint and vsphere_provider.username are required when the provider is enabled (vSphere has no ambient identity)."
  }
}

variable "vsphere_password" {
  description = "vSphere password the gateway's vsphere provider authenticates with. Point it at a READ-ONLY role — discovery only reads VM properties (name, power state, guest info, uuid, Notes). Optional, because a child on vSphere need not discover BY vSphere: the docker-provider leg runs the same module with vsphere_provider.enabled = false and has no business carrying a vCenter secret."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = !var.vsphere_provider.enabled || var.vsphere_password != ""
    error_message = "vsphere_password is required when vsphere_provider.enabled (vSphere has no ambient identity — no instance profile, managed identity or IMDS to fall back on)."
  }
}

variable "vmoperator_provider" {
  description = <<-EOT
    Traefik Hub vmoperator provider configuration (hub.providers.vmoperator) — discovery of
    VM Service VMs on KUBERNETES terms. The provider lists vmoperator.vmware.com
    VirtualMachine CRs in the given Supervisor namespaces and reads each VM's routing
    intent from ONE annotation on the CR (label_annotation, default `traefik.io/config`)
    as the same LINE-FORMAT `traefik.<key>=<value>` block the vsphere provider reads from
    a VM's Notes. The backend address is status.network.primaryIP4. Same-named services
    across VMs MERGE into one load balancer.

    The credential is a NAMESPACE-SCOPED ServiceAccount token delivered as a FILE
    (token_file): mint the SA + Role(get/list/watch virtualmachines) + a long-lived
    token Secret against the Supervisor, and hand the token to this module through
    extra_files at a path under /data (in preview mode only /data and
    /etc/traefik-hub/dynamic are bind-mounted into the container). No vCenter
    credential is involved anywhere on this leg.

      exposed_by_default  false: a VM is published only when its annotation carries
                          traefik.enable=true (the gateway VM itself, cluster nodes and
                          unrelated machines never become backends by accident).
      constraints         a Traefik constraints expression over the parsed labels, e.g.
                          Label(`traefik.tags`, `vmsvc`).
      namespaces          REQUIRED: a namespace-scoped token cannot list cluster-wide.
      api_version         the served vmoperator.vmware.com version to read ("" = the
                          provider default).
  EOT
  type = object({
    enabled              = optional(bool, false)
    endpoint             = optional(string, "")
    token_file           = optional(string, "/data/vmoperator-token")
    namespaces           = optional(list(string), [])
    insecure_skip_verify = optional(bool, true)
    exposed_by_default   = optional(bool, false)
    constraints          = optional(string, "")
    default_rule         = optional(string, "")
    label_annotation     = optional(string, "traefik.io/config")
    api_version          = optional(string, "")
    refresh_seconds      = optional(number, null)
  })
  default = {}

  validation {
    condition     = !var.vmoperator_provider.enabled || (var.vmoperator_provider.endpoint != "" && length(var.vmoperator_provider.namespaces) > 0)
    error_message = "vmoperator_provider.endpoint and at least one entry in vmoperator_provider.namespaces are required when the provider is enabled (a namespace-scoped Supervisor token cannot list cluster-wide)."
  }
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
  description = "Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. vsphere)"
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

variable "ssh_public_key" {
  type        = string
  description = "Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt."
  default     = ""
}
