# =============================================================================
# vSphere VM Traefik Deployment — the multicluster CHILD on vSphere
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2 and traefik/azure-vm.
# One VM cloned from a cloud-init-enabled Ubuntu cloud-image template runs the
# Hub image; its vsphere provider (--hub.providers.vsphere) discovers workload
# VMs by their `guestinfo.traefik` extraConfig entry (a JSON object of Traefik
# labels). vSphere has NO ambient identity (no instance profile / managed
# identity), so the provider authenticates with explicit vCenter credentials —
# var.vsphere_password is the one secret this module carries.
# =============================================================================

locals {
  # hub.providers.vsphere static config as CLI flags (same delivery as the
  # azureVM/oci args in the sibling modules). Endpoint may be a bare vCenter
  # host — the provider applies the SDK defaults (https scheme, /sdk path).
  # hub.providers.vsphere static config as CLI flags. The provider discovers service
  # membership from vCenter TAGS (serviceNameCategoryKey) and takes its routers/services
  # from a base configuration pulled over configEndpoint (GitOps) or read from filename —
  # there are no per-VM label flags (constraints / exposedByDefault / defaultRule) any
  # more, because VMs no longer carry labels.
  vsphere_provider_args = var.vsphere_provider.enabled ? concat(
    [
      "--hub.providers.vsphere=true",
      "--hub.providers.vsphere.endpoint=${var.vsphere_provider.endpoint}",
      "--hub.providers.vsphere.username=${var.vsphere_provider.username}",
      "--hub.providers.vsphere.password=${var.vsphere_password}",
      "--hub.providers.vsphere.ipMode=${var.vsphere_provider.ip_mode}",
      "--hub.providers.vsphere.serviceNameCategoryKey=${var.vsphere_provider.service_name_category_key}",
    ],
    var.vsphere_provider.insecure_skip_verify ? ["--hub.providers.vsphere.insecureSkipVerify=true"] : [],
    var.vsphere_provider.datacenter != "" ? ["--hub.providers.vsphere.datacenter=${var.vsphere_provider.datacenter}"] : [],
    var.vsphere_provider.config_endpoint != "" ? ["--hub.providers.vsphere.configEndpoint=${var.vsphere_provider.config_endpoint}"] : [],
    var.vsphere_provider.config_insecure_skip_verify ? ["--hub.providers.vsphere.configTLS.insecureSkipVerify=true"] : [],
    var.vsphere_provider.filename != "" ? ["--hub.providers.vsphere.filename=${var.vsphere_provider.filename}"] : [],
    var.vsphere_provider.refresh_seconds != null ? ["--hub.providers.vsphere.refreshSeconds=${var.vsphere_provider.refresh_seconds}"] : [],
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
    # Gate on the CALLER's var.otlp_address, not module.config.otlp_endpoint: the
    # latter falls back to "http://opentelemetry-collector:4318" and is NEVER empty,
    # so this condition was always true -- every deployment that did not configure
    # OTLP still blocked in cloud-init for the gate's full 30-minute budget (180
    # rounds x 10s) waiting for a collector that was never going to exist.
    collector_gate       = var.otlp_address != "" ? templatefile("${path.module}/../../cloud-init-snippets/otlp-collector-gate.sh.tpl", { otlp_address = module.config.otlp_endpoint, rounds = 180, verify_tls = false }) : ""
    traefik_hub_version  = module.config.image_tag
    arch                 = "amd64"
    cli_arguments        = local.cli_arguments
    env_vars             = local.env_vars_list
    file_provider_config = var.file_provider_config
    extra_files          = var.extra_files
    # Not offered by this module: only a guest whose ROOT is too small for the container
    # engine needs one (a KubeVirt containerDisk is fixed at the image's virtual size).
    # The key must still be passed -- templatefile hard-errors on a key the template uses
    # but the caller omits, which is how adding it to ONE of the nine renderers broke the
    # other eight.
    data_disk           = null
    mount_docker_socket = var.mount_docker_socket
    ssh_public_key      = var.ssh_public_key
    extra_runcmd        = var.extra_runcmd
    performance_tuning  = local.performance_tuning
    # Feeds the template's own %{ if otlp_address != "" } guard: pass the caller's
    # raw value so the gate block only renders when OTLP is actually configured.
    otlp_address        = var.otlp_address
    instance_name       = local.instance_key
    dashboard_config    = "" # Optional
    vip                 = "" # Optional
    keepalived_priority = 100
    network_interface   = "ens192" # vmxnet3 NIC name on Ubuntu cloud images
    dns_traefiker       = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode = var.enable_preview_mode
    preview_image       = module.config.image_full
  })

  # Self-register the Traefik VM's own dashboard via its vsphere provider
  # (-> dashboard@vsphere) — the tag-based siblings' trick, as guestinfo JSON.
  # Disable when the dashboard is advertised another way (e.g. a file-rule
  # uplink): without traefik.enable the VM isn't self-discovered at all.
  self_labels = var.enable_dashboard_discovery ? {
    "traefik.enable"                                           = "true"
    "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
    "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
    "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
  } : {}

  traefik_labels = merge(local.self_labels, var.extra_labels)
}

# One gateway VM cloned from the shared compute/vsphere/vm module. This caller
# still renders the cloud-init (local.user_data) and builds the vsphere
# provider's workload config (local.traefik_labels -> guestinfo.traefik); the
# module owns the vsphere_virtual_machine resource and its data lookups.
module "compute" {
  source = "../../compute/vsphere/vm"

  datacenter    = var.datacenter
  datastore     = var.datastore
  cluster       = var.cluster
  resource_pool = var.resource_pool
  network       = var.network
  template      = var.template
  folder        = var.folder

  num_cpus  = var.num_cpus
  memory    = var.memory
  disk_size = var.disk_size

  # One VM keyed "<vm_name>-1" (matches the previous single-instance name).
  apps = {
    (var.vm_name) = { replicas = 1 }
  }

  user_data = {
    (local.instance_key) = local.user_data
  }

  # The vsphere provider's `guestinfo.traefik` entry — omitted when no labels,
  # exactly as before.
  extra_config = {
    (local.instance_key) = length(local.traefik_labels) > 0 ? { "guestinfo.traefik" = jsonencode(local.traefik_labels) } : {}
  }
}

# =============================================================================
# Shared Configuration Module - vSphere VM
# =============================================================================
# vSphere VM uses extracted config from helm template (extract_config=true),
# exactly like EC2 and Azure VM. Shared variables are defined in variables.tf
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
  custom_arguments     = concat(var.custom_arguments, local.vsphere_provider_args)
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
