# =============================================================================
# Proxmox VE VM Traefik Deployment — the multicluster CHILD on Proxmox
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2 and traefik/vsphere-vm.
# One VM cloned from a cloud-init-enabled Ubuntu cloud-image template runs the
# Hub image, and guest discovery is the NATIVE first-party Hub Proxmox VE provider
# (like ec2/azurevm/gce), delivered as static-config CLI flags:
#   --hub.providers.proxmox.*                               (endpoint/token/filters)
# It is a compiled-in provider (static CLI flags), so the VM needs no outbound
# internet at boot. The provider reads LINE-FORMAT traefik.* labels (one
# `traefik.key=value` per line) from each guest's Notes/description and resolves
# QEMU IPs via the guest agent, LXC IPs via the container interfaces API — and
# guest_types scopes each gateway to one compute type. Proxmox has no ambient
# identity (no instance profile / managed
# identity), so it authenticates with an explicit PVE API token — var.proxmox_api_token
# is the one secret this module carries.
# =============================================================================

locals {
  # The native provider's static config as CLI flags (same delivery as the ec2/azurevm/gce
  # sibling modules: --hub.providers.<name>.*). Its services surface as <name>@proxmox.
  # NB api_validate_ssl -> insecureSkipVerify is INVERTED, and poll_interval (a duration
  # string on the old plugin) is now refresh_seconds (an int). guest_types filters this
  # gateway to one compute type — the plugin could not, so it discovered every guest.
  proxmox_provider_args = var.proxmox_provider.enabled ? concat(
    [
      "--hub.providers.proxmox=true",
      "--hub.providers.proxmox.endpoint=${var.proxmox_provider.endpoint}",
      "--hub.providers.proxmox.tokenID=${var.proxmox_provider.token_id}",
      "--hub.providers.proxmox.tokenSecret=${var.proxmox_api_token}",
      "--hub.providers.proxmox.insecureSkipVerify=${var.proxmox_provider.insecure_skip_verify}",
      "--hub.providers.proxmox.refreshSeconds=${var.proxmox_provider.refresh_seconds}",
      "--hub.providers.proxmox.exposedByDefault=${var.proxmox_provider.exposed_by_default}",
      "--hub.providers.proxmox.ipMode=${var.proxmox_provider.ip_mode}",
    ],
    length(var.proxmox_provider.guest_types) > 0 ? ["--hub.providers.proxmox.guestTypes=${join(",", var.proxmox_provider.guest_types)}"] : [],
    length(var.proxmox_provider.nodes) > 0 ? ["--hub.providers.proxmox.nodes=${join(",", var.proxmox_provider.nodes)}"] : [],
    var.proxmox_provider.tag_filter != "" ? ["--hub.providers.proxmox.tagFilter=${var.proxmox_provider.tag_filter}"] : [],
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
    # Shared cloud-init snippets, rendered here and injected pre-rendered
    # (templatefile has no include; see terraform/cloud-init-snippets/README.md).
    docker_install = file("${path.module}/../../cloud-init-snippets/docker-install.sh.tpl")
    collector_gate = module.config.otlp_endpoint != "" ? templatefile("${path.module}/../../cloud-init-snippets/otlp-collector-gate.sh.tpl", { otlp_address = module.config.otlp_endpoint }) : ""
    # Inert here: only the docker-provider leg needs the socket bound in or extra
    # containers provisioned. The shared template requires both keys regardless --
    # templatefile hard-errors on a key the template uses but the caller omits.
    # Not offered by this module: only a guest whose ROOT is too small for the container
    # engine needs one (a KubeVirt containerDisk is fixed at the image's virtual size).
    # The key must still be passed -- templatefile hard-errors on a key the template uses
    # but the caller omits, which is how adding it to ONE of the nine renderers broke the
    # other eight.
    data_disk            = null
    mount_docker_socket  = false
    ssh_public_key       = var.ssh_public_key
    extra_runcmd         = []
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

  # Self-register the Traefik VM's own dashboard via the native provider (-> the
  # dashboard router/service on @proxmox) — the siblings' trick. Delivered as
  # LINE-FORMAT traefik.* labels in the Notes (same grammar as the whoami guests).
  # Disable when the dashboard is advertised another way (e.g. a file-rule uplink):
  # with no traefik.enable the VM isn't self-discovered at all.
  self_labels = var.enable_dashboard_discovery ? {
    "traefik.enable"                                           = "true"
    "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
    "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
    "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
  } : {}

  traefik_labels = merge(local.self_labels, var.extra_labels)
  description    = length(local.traefik_labels) > 0 ? join("\n", [for k, v in local.traefik_labels : "${k}=${v}"]) : ""
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
  custom_arguments     = concat(var.custom_arguments, local.proxmox_provider_args)
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
