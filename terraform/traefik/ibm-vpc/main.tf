# =============================================================================
# IBM VPC Traefik Deployment — the multicluster CHILD on IBM Cloud VPC
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2, traefik/oci-vm and
# traefik/alibaba-ecs. One virtual server instance runs the Hub image as a
# docker container (the cloud-init preview-image path).
#
# The ibmVPC provider is DIFFERENT from the other VM providers twice over:
#   1. No ambient identity — IBM VSIs expose no metadata credential the
#      provider consumes, so an IAM API key (var.ibmcloud_api_key) is passed
#      honestly as --hub.providers.ibmVPC.apiKey.
#   2. No per-instance traefik.* tags — routers/services/middlewares live in a
#      BASE CONFIGURATION FILE (var.base_config_content) shipped to the VM via
#      the cloud-init extra_files mechanism and referenced with
#      --hub.providers.ibmVPC.filename. The provider fills each service's
#      servers with the instances tagged "<serviceNameTagKey>:<service>", and
#      fsnotify-watches the file for hot reloads.
# =============================================================================

data "ibm_is_subnet" "traefik" {
  identifier = var.subnet_id
}

locals {
  # Default the provider's discovery scope to the instance's own region and
  # VPC, both derived from the subnet it joins (zone "us-south-1" -> region
  # "us-south").
  provider_region = var.ibmvpc_provider.region != "" ? var.ibmvpc_provider.region : regex("^(.*)-\\d+$", data.ibm_is_subnet.traefik.zone)[0]
  provider_vpc_id = var.ibmvpc_provider.vpc_id != "" ? var.ibmvpc_provider.vpc_id : data.ibm_is_subnet.traefik.vpc

  # hub.providers.ibmVPC static config as CLI flags (same delivery as the
  # alibabaECS flags in traefik/alibaba-ecs; casing verified against the
  # provider's json tags: ibmVPC, apiKey, searchEndpoint, vpcID,
  # serviceNameTagKey, ipMode, pollInterval, filename).
  ibmvpc_provider_args = var.ibmvpc_provider.enabled ? concat(
    [
      "--hub.providers.ibmVPC=true",
      "--hub.providers.ibmVPC.apiKey=${var.ibmcloud_api_key}",
      "--hub.providers.ibmVPC.region=${local.provider_region}",
      "--hub.providers.ibmVPC.vpcID=${local.provider_vpc_id}",
      "--hub.providers.ibmVPC.ipMode=${var.ibmvpc_provider.ip_mode}",
      "--hub.providers.ibmVPC.filename=${var.base_config_path}",
    ],
    var.ibmvpc_provider.endpoint != "" ? ["--hub.providers.ibmVPC.endpoint=${var.ibmvpc_provider.endpoint}"] : [],
    var.ibmvpc_provider.search_endpoint != "" ? ["--hub.providers.ibmVPC.searchEndpoint=${var.ibmvpc_provider.search_endpoint}"] : [],
    var.ibmvpc_provider.service_name_tag_key != "" ? ["--hub.providers.ibmVPC.serviceNameTagKey=${var.ibmvpc_provider.service_name_tag_key}"] : [],
    var.ibmvpc_provider.poll_interval != "" ? ["--hub.providers.ibmVPC.pollInterval=${var.ibmvpc_provider.poll_interval}"] : [],
  ) : []

  # The base configuration file rides the cloud-init extra_files transport
  # (the same write_files mechanism traefik/ec2 uses for the file-provider
  # config, just a different target path). It must NOT land under
  # /etc/traefik-hub/dynamic — the file provider watches that directory and
  # would double-load the routers with empty services. /data is mounted into
  # the preview-mode container (-v /data:/data), so the path works in both the
  # container and host-binary run modes.
  base_config_files = var.ibmvpc_provider.enabled && var.base_config_content != "" ? [
    {
      path    = var.base_config_path
      content = var.base_config_content
    }
  ] : []

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
    extra_files          = concat(var.extra_files, local.base_config_files)
    performance_tuning   = local.performance_tuning
    otlp_address         = module.config.otlp_endpoint
    instance_name        = local.instance_key
    dashboard_config     = "" # Optional
    vip                  = "" # Optional
    keepalived_priority  = 100
    network_interface    = "ens3" # IBM VPC gen2 Ubuntu default NIC name
    dns_traefiker        = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode  = var.enable_preview_mode
    preview_image        = module.config.image_full
  })
}

# Latest stock Ubuntu 24.04 amd64 image — the same OS the alibaba-ecs/oci-vm
# siblings run (the cloud-init installs docker via apt). IBM has no
# server-side name wildcard, so filter the public catalog locally.
data "ibm_is_images" "ubuntu" {
  count = var.image_id != "" ? 0 : 1

  status     = "available"
  visibility = "public"
}

locals {
  ubuntu_image_names = var.image_id != "" ? [] : sort([
    for img in data.ibm_is_images.ubuntu[0].images :
    img.name if can(regex("^ibm-ubuntu-24-04(-\\d+)?-minimal-amd64", img.name))
  ])

  image_id = var.image_id != "" ? var.image_id : [
    for img in data.ibm_is_images.ubuntu[0].images :
    img.id if img.name == element(local.ubuntu_image_names, length(local.ubuntu_image_names) - 1)
  ][0]
}

# Escape hatch mirroring traefik/alibaba-ecs's enable_security_group: a
# security group opening the demo ports (incl. the :9443 uplink the parent
# dials) from security_group_source_cidr. Off by default — compute/ibm/vpc's
# group already opens them. IBM security groups deny egress by default, so the
# module-created group also carries an allow-all outbound rule (image pulls).
resource "ibm_is_security_group" "traefik" {
  count = var.enable_security_group ? 1 : 0

  name           = "${var.vm_name}-sg"
  vpc            = data.ibm_is_subnet.traefik.vpc
  resource_group = var.resource_group_id != "" ? var.resource_group_id : null
}

resource "ibm_is_security_group_rule" "ingress" {
  for_each = var.enable_security_group ? { for port in var.security_group_ingress_ports : tostring(port) => port } : {}

  group     = ibm_is_security_group.traefik[0].id
  direction = "inbound"
  remote    = var.security_group_source_cidr

  tcp {
    port_min = each.value
    port_max = each.value
  }
}

resource "ibm_is_security_group_rule" "egress" {
  count = var.enable_security_group ? 1 : 0

  group     = ibm_is_security_group.traefik[0].id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

resource "ibm_is_instance" "traefik" {
  name    = local.instance_key
  image   = local.image_id
  profile = var.instance_profile

  vpc            = data.ibm_is_subnet.traefik.vpc
  zone           = data.ibm_is_subnet.traefik.zone
  resource_group = var.resource_group_id != "" ? var.resource_group_id : null
  keys           = var.ssh_key_ids

  primary_network_interface {
    subnet          = var.subnet_id
    security_groups = concat(var.security_group_ids, var.enable_security_group ? [ibm_is_security_group.traefik[0].id] : [])
  }

  # IBM takes cloud-init user data as plain text (no base64).
  user_data = local.user_data

  # Flat string user tags only — no dotted traefik.* tags exist on IBM, so
  # there is no tag-based dashboard self-discovery here. Advertise the
  # dashboard via file_provider_config / base_config_content instead.
  tags = var.extra_tags

  lifecycle {
    precondition {
      condition     = !var.ibmvpc_provider.enabled || var.ibmcloud_api_key != ""
      error_message = "ibmcloud_api_key must be set when the ibmVPC provider is enabled (IBM has no ambient instance identity the provider can use)."
    }

    precondition {
      condition     = !var.ibmvpc_provider.enabled || var.base_config_content != ""
      error_message = "base_config_content must be set when the ibmVPC provider is enabled (the provider requires a base configuration file at --hub.providers.ibmVPC.filename)."
    }
  }
}

# Inbound-only convenience (public entrypoints / dashboard). Off by default —
# the parent dials the private IP :9443 in-VPC, and image pulls ride the
# subnet's public gateway.
resource "ibm_is_floating_ip" "traefik" {
  count = var.enable_floating_ip ? 1 : 0

  name   = "${local.instance_key}-fip"
  target = ibm_is_instance.traefik.primary_network_interface[0].id
}

# =============================================================================
# Shared Configuration Module - IBM VPC
# =============================================================================
# IBM VPC uses extracted config from helm template (extract_config=true),
# exactly like EC2, OCI VM and Alibaba ECS. Shared variables are defined here
# alongside the module instantiation.
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
  custom_arguments     = concat(var.custom_arguments, local.ibmvpc_provider_args)
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
