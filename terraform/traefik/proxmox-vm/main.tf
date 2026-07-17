# =============================================================================
# Proxmox VE VM Traefik Deployment — the multicluster CHILD on Proxmox
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2 and traefik/vsphere-vm.
# One VM cloned from a cloud-init-enabled Ubuntu cloud-image template runs the
# Hub image — but guest discovery is NOT a first-party hub provider here: it's
# the open-source Yaegi PROVIDER PLUGIN github.com/NX211/traefik-proxmox-provider
# (a catalog plugin, so any stock Traefik/Hub image runs it — no custom build),
# delivered as static-config CLI flags:
#   --experimental.plugins.proxmox.moduleName / .version    (plugin download)
#   --providers.plugin.proxmox.*                            (plugin config)
# Traefik downloads + interprets the plugin from plugins.traefik.io at start
# (Yaegi), so the VM NEEDS OUTBOUND INTERNET or Traefik exits. Proxmox has no
# ambient identity (no instance profile / managed identity), so the plugin
# authenticates with an explicit PVE API token — var.proxmox_api_token is the
# one secret this module carries.
# =============================================================================

locals {
  # The plugin's static config as CLI flags (same delivery as the vsphere/oci
  # provider args in the sibling modules). Keys map 1:1 to the plugin's
  # documented config: pollInterval, apiEndpoint, apiTokenId, apiToken,
  # apiLogging, apiValidateSSL. Its services surface as <name>@plugin-proxmox.
  proxmox_plugin_args = var.proxmox_plugin.enabled ? concat(
    [
      "--experimental.plugins.proxmox.moduleName=github.com/NX211/traefik-proxmox-provider",
      "--experimental.plugins.proxmox.version=${var.proxmox_plugin.version}",
      "--providers.plugin.proxmox.pollInterval=${var.proxmox_plugin.poll_interval}",
      "--providers.plugin.proxmox.apiEndpoint=${var.proxmox_plugin.api_endpoint}",
      "--providers.plugin.proxmox.apiTokenId=${var.proxmox_plugin.api_token_id}",
      "--providers.plugin.proxmox.apiToken=${var.proxmox_api_token}",
      "--providers.plugin.proxmox.apiValidateSSL=${var.proxmox_plugin.api_validate_ssl}",
    ],
    var.proxmox_plugin.api_logging != "" ? ["--providers.plugin.proxmox.apiLogging=${var.proxmox_plugin.api_logging}"] : [],
  ) : []

  # Use extracted CLI arguments from Helm template (includes file provider if configured)
  # Filter out placeholder token arg to avoid duplicates with manual injection in Systemd unit
  cli_arguments = [
    for arg in module.config.extracted_cli_args_cloud :
    arg if !startswith(arg, "--hub.token=")
  ]

  # Merge standard env vars with explicit HUB_TOKEN injection (EC2 pattern)
  env_vars_list = concat(
    module.config.env_vars_list,
    module.config.traefik_hub_token != "" ? [{ name = "HUB_TOKEN", value = module.config.traefik_hub_token }] : []
  )

  # Normalize performance tuning with defaults
  performance_tuning = {
    limit_nofile        = coalesce(try(var.performance_tuning.limit_nofile, null), 500000)
    tcp_tw_reuse        = coalesce(try(var.performance_tuning.tcp_tw_reuse, null), 1)
    tcp_timestamps      = coalesce(try(var.performance_tuning.tcp_timestamps, null), 1)
    rmem_max            = coalesce(try(var.performance_tuning.rmem_max, null), 16777216)
    wmem_max            = coalesce(try(var.performance_tuning.wmem_max, null), 16777216)
    somaxconn           = coalesce(try(var.performance_tuning.somaxconn, null), 4096)
    netdev_max_backlog  = coalesce(try(var.performance_tuning.netdev_max_backlog, null), 4096)
    ip_local_port_range = coalesce(try(var.performance_tuning.ip_local_port_range, null), "1024 65535")
    gomaxprocs          = coalesce(try(var.performance_tuning.gomaxprocs, null), 0)
    gogc                = coalesce(try(var.performance_tuning.gogc, null), 100)
    numa_node           = coalesce(try(var.performance_tuning.numa_node, null), -1)
  }

  instance_key = "${var.vm_name}-1"

  user_data = templatefile("${path.module}/../cloud-init/cloud-init.tpl", {
    traefik_hub_version  = module.config.image_tag
    arch                 = "amd64"
    cli_arguments        = local.cli_arguments
    env_vars             = local.env_vars_list
    file_provider_config = var.file_provider_config
    extra_files          = var.extra_files
    performance_tuning   = local.performance_tuning
    otlp_address         = module.config.otlp_endpoint
    instance_name        = local.instance_key
    dashboard_config     = "" # Optional
    vip                  = "" # Optional
    keepalived_priority  = 100
    network_interface    = "ens18" # virtio NIC name on Ubuntu cloud images under PVE's default PCI layout
    dns_traefiker        = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode  = var.enable_preview_mode
    preview_image        = module.config.image_full
  })

  # Self-register the Traefik VM's own dashboard via the plugin (-> the
  # dashboard router/service on @plugin-proxmox) — the siblings' trick, in the
  # NX211 LINE format (one traefik.key=value per line in the Notes). Disable
  # when the dashboard is advertised another way (e.g. a file-rule uplink):
  # without traefik.enable the VM isn't self-discovered at all.
  self_labels = var.enable_dashboard_discovery ? {
    "traefik.enable"                                           = "true"
    "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
    "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
    "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
  } : {}

  traefik_labels = merge(local.self_labels, var.extra_labels)
  description    = join("\n", [for k, v in local.traefik_labels : "${k}=${v}"])
}

# =============================================================================
# The QEMU VM — the shared compute/proxmox/vm primitive
# =============================================================================
# One VM cloned from the cloud-init template, running the rendered user-data
# above. The snippet upload, its content-hashed file name, and the
# replace_triggered_by that recreates the VM on a user-data change all live in
# the module (they are infra); this caller only renders the user-data and the
# self-registration Notes and reads the agent-reported guest IP back out.
module "vm" {
  source = "../../compute/proxmox/vm"

  node_name            = var.node_name
  datastore_id         = var.datastore_id
  snippet_datastore_id = var.snippet_datastore_id
  bridge               = var.bridge
  template_vm_id       = var.template_vm_id
  template_name        = var.template_name
  num_cpus             = var.num_cpus
  cpu_type             = var.cpu_type
  memory               = var.memory
  disk_size            = var.disk_size
  disk_interface       = var.disk_interface

  instances = {
    (local.instance_key) = {
      user_data   = local.user_data
      description = length(local.traefik_labels) > 0 ? local.description : null
    }
  }
}

# =============================================================================
# Shared Configuration Module - Proxmox VM
# =============================================================================
# Proxmox VM uses extracted config from helm template (extract_config=true),
# exactly like EC2 and vSphere VM. Shared variables are defined in variables.tf
# alongside the platform-specific ones.
# =============================================================================

module "config" {
  source = "../shared"

  # Extract config - the VM needs CLI args, env vars from Helm template
  extract_config = true

  # Feature Flags
  enable_api_gateway    = var.enable_api_gateway
  enable_ai_gateway     = var.enable_ai_gateway
  enable_mcp_gateway    = var.enable_mcp_gateway
  enable_api_management = false # K8s only
  enable_offline_mode   = var.enable_offline_mode
  enable_preview_mode   = var.enable_preview_mode
  enable_debug          = var.enable_debug

  # Versions & Images
  traefik_chart_version   = var.traefik_chart_version
  traefik_tag             = var.traefik_tag
  traefik_hub_tag         = var.traefik_hub_tag
  traefik_hub_preview_tag = var.traefik_hub_preview_tag
  custom_image_registry   = var.custom_image_registry
  custom_image_repository = var.custom_image_repository
  custom_image_tag        = var.custom_image_tag

  # Observability
  log_level                    = var.log_level
  otlp_address                 = var.otlp_address
  otlp_service_name            = var.otlp_service_name
  enable_otlp_access_logs      = var.enable_otlp_access_logs
  enable_otlp_application_logs = var.enable_otlp_application_logs
  enable_otlp_metrics          = var.enable_otlp_metrics
  enable_otlp_traces           = var.enable_otlp_traces
  enable_prometheus            = var.enable_prometheus
  enable_access_logs           = var.enable_access_logs

  # Plugins & Extensions
  custom_plugins       = var.custom_plugins
  custom_ports         = var.custom_ports
  custom_arguments     = concat(var.custom_arguments, local.proxmox_plugin_args)
  custom_envs          = var.custom_envs
  file_provider_config = var.file_provider_config
  file_provider_path   = var.file_provider_path

  # Licensing
  traefik_hub_token = var.traefik_hub_token

  # Dashboard
  enable_dashboard      = var.enable_dashboard
  dashboard_insecure    = var.dashboard_insecure
  dashboard_entrypoints = var.dashboard_entrypoints
  dashboard_match_rule  = var.dashboard_match_rule

  # Providers
  multicluster_provider = var.multicluster_provider
}
