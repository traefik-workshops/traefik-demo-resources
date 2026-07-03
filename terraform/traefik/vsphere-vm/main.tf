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
  vsphere_provider_args = var.vsphere_provider.enabled ? concat(
    [
      "--hub.providers.vsphere=true",
      "--hub.providers.vsphere.endpoint=${var.vsphere_provider.endpoint}",
      "--hub.providers.vsphere.username=${var.vsphere_provider.username}",
      "--hub.providers.vsphere.password=${var.vsphere_password}",
      "--hub.providers.vsphere.ipMode=${var.vsphere_provider.ip_mode}",
      "--hub.providers.vsphere.exposedByDefault=${var.vsphere_provider.exposed_by_default}",
    ],
    var.vsphere_provider.insecure_skip_verify ? ["--hub.providers.vsphere.insecureSkipVerify=true"] : [],
    var.vsphere_provider.datacenter != "" ? ["--hub.providers.vsphere.datacenter=${var.vsphere_provider.datacenter}"] : [],
    var.vsphere_provider.default_rule != "" ? ["--hub.providers.vsphere.defaultRule=${var.vsphere_provider.default_rule}"] : [],
    var.vsphere_provider.constraints != "" ? ["--hub.providers.vsphere.constraints=${var.vsphere_provider.constraints}"] : [],
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
    network_interface    = "ens192" # vmxnet3 NIC name on Ubuntu cloud images
    dns_traefiker        = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode  = var.enable_preview_mode
    preview_image        = module.config.image_full
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

data "vsphere_datacenter" "this" {
  name = var.datacenter
}

data "vsphere_datastore" "this" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_compute_cluster" "this" {
  count         = var.resource_pool == "" ? 1 : 0
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_resource_pool" "this" {
  count         = var.resource_pool != "" ? 1 : 0
  name          = var.resource_pool
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_network" "this" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template
  datacenter_id = data.vsphere_datacenter.this.id
}

locals {
  resource_pool_id = var.resource_pool != "" ? data.vsphere_resource_pool.this[0].id : data.vsphere_compute_cluster.this[0].resource_pool_id
}

resource "vsphere_virtual_machine" "traefik" {
  name             = local.instance_key
  resource_pool_id = local.resource_pool_id
  datastore_id     = data.vsphere_datastore.this.id
  folder           = var.folder != "" ? var.folder : null

  num_cpus = var.num_cpus
  memory   = var.memory

  # Inherit the template's hardware identity so the clone boots unchanged.
  guest_id  = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type
  firmware  = data.vsphere_virtual_machine.template.firmware

  network_interface {
    network_id   = data.vsphere_network.this.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label = "disk0"
    # Never below the template's disk — vSphere refuses to shrink on clone.
    size             = max(data.vsphere_virtual_machine.template.disks[0].size, var.disk_size)
    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks[0].eagerly_scrub
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  extra_config = merge(
    {
      "guestinfo.userdata"          = base64encode(local.user_data)
      "guestinfo.userdata.encoding" = "base64"
      "guestinfo.metadata"          = base64encode(jsonencode({ "instance-id" = local.instance_key, "local-hostname" = local.instance_key }))
      "guestinfo.metadata.encoding" = "base64"
    },
    length(local.traefik_labels) > 0 ? { "guestinfo.traefik" = jsonencode(local.traefik_labels) } : {}
  )

  # The parent dials this VM's guest IP (:9443 uplink) — reported by
  # open-vm-tools, which the Ubuntu cloud images ship.
  wait_for_guest_net_timeout = 10
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
