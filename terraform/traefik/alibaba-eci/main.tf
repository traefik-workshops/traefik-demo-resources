# =============================================================================
# Alibaba ECI Traefik Deployment — the multicluster CHILD on Elastic Container
# Instance
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template), exactly like
# traefik/aci and traefik/oci-ci. The child IS an ECI container group running
# the Hub image with the hub.providers.alibabaECI provider enabled; the parent
# dials the group's private vswitch IP on :9443.
#
# AUTH — keyless by default: ECI container groups take a ram_role_name
# (trusted by ecs.aliyuncs.com — ECI serves the same 100.100.100.200 metadata
# endpoint as ECS), and the provider's empty-credential default chain (env ->
# profile -> RAM role via metadata) consumes it. Access-key variables exist as
# a fallback for accounts where RAM roles can't be created.
# =============================================================================

data "alicloud_regions" "current" {
  current = true
}

locals {
  # Default the provider's discovery scope to the group's own region.
  provider_region = var.alibabaeci_provider.region_id != "" ? var.alibabaeci_provider.region_id : data.alicloud_regions.current.regions[0].id

  # hub.providers.alibabaECI static config as CLI flags (same delivery as the
  # ocici flags in traefik/oci-ci). Keys are only injected when the RAM role
  # fallback is needed; empty credentials mean the default chain.
  alibabaeci_provider_args = var.alibabaeci_provider.enabled ? concat(
    [
      "--hub.providers.alibabaECI=true",
      "--hub.providers.alibabaECI.regionID=${local.provider_region}",
      "--hub.providers.alibabaECI.ipMode=${var.alibabaeci_provider.ip_mode}",
      "--hub.providers.alibabaECI.exposedByDefault=${var.alibabaeci_provider.exposed_by_default}",
    ],
    var.alibabaeci_provider.endpoint != "" ? ["--hub.providers.alibabaECI.endpoint=${var.alibabaeci_provider.endpoint}"] : [],
    var.access_key_id != "" ? ["--hub.providers.alibabaECI.accessKeyID=${var.access_key_id}"] : [],
    var.access_key_secret != "" ? ["--hub.providers.alibabaECI.accessKeySecret=${var.access_key_secret}"] : [],
    var.security_token != "" ? ["--hub.providers.alibabaECI.securityToken=${var.security_token}"] : [],
    var.alibabaeci_provider.default_rule != "" ? ["--hub.providers.alibabaECI.defaultRule=${var.alibabaeci_provider.default_rule}"] : [],
    var.alibabaeci_provider.constraints != "" ? ["--hub.providers.alibabaECI.constraints=${var.alibabaeci_provider.constraints}"] : [],
    var.alibabaeci_provider.refresh_seconds != null ? ["--hub.providers.alibabaECI.refreshSeconds=${var.alibabaeci_provider.refresh_seconds}"] : [],
    # Without portDiscovery the provider needs explicit port tags; with it,
    # it falls back to the group's lowest declared container port.
    var.alibabaeci_provider.port_discovery ? ["--hub.providers.alibabaECI.portDiscovery=true"] : [],
  ) : []

  # Use extracted CLI arguments from Helm template
  # Uses centralized filtering to exclude Kubernetes-specific args
  traefik_arguments = module.config.extracted_cli_args_cloud

  # Use shared module for image reference
  traefik_image = module.config.image_full

  # All entrypoint ports plus the uplink :9443 — reachability of the declared
  # ports is governed by the attached security group.
  exposed_ports = distinct(concat(module.config.ports_list, [9443]))

  # The shared module strips --hub.token from the extracted args so it can be
  # injected per-platform. ECI `commands` REPLACES the image entrypoint (like
  # ACI `commands`) and is exec'd with no shell, so the token value is inlined
  # in `args` rather than read from an env var.
  arguments = concat(
    ["--hub.token=${var.traefik_hub_token}"],
    local.traefik_arguments
  )

  # Build tags including ports — the alibabaECI provider's workload config,
  # exactly like the ACI group's Azure tags.
  discovery_tags = merge(var.extra_tags, {
    for name, port in module.config.ports :
    "traefik.http.routers.${name}.entrypoints" => name
    if try(port.expose.default, false)
    },
    # Self-register the Traefik group's own dashboard via its alibabaECI
    # provider (-> dashboard@alibabaeci). Disable when the dashboard is
    # advertised another way (e.g. a file-rule uplink): without traefik.enable
    # the group isn't self-discovered at all, so no redundant self-router
    # appears.
    var.enable_dashboard_discovery ? {
      "traefik.enable"                                           = "true"
      "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
      "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
      "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
  } : {})
}

# The alibabaECI provider's keyless credential: a RAM role (trusted by
# ecs.aliyuncs.com — the trust ECI's metadata mechanism requires) with
# read-only ECI Describe rights. RAM names are account-global — disable when
# the demo already created them under the same name elsewhere.
resource "alicloud_ram_role" "traefik" {
  count = var.enable_ram_role ? 1 : 0

  role_name   = "${var.name}-alibabaeci-role"
  description = "Traefik Hub alibabaECI provider discovery (read-only ECI)"

  assume_role_policy_document = jsonencode({
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["ecs.aliyuncs.com"]
        }
      }
    ]
    Version = "1"
  })
}

resource "alicloud_ram_policy" "traefik" {
  count = var.enable_ram_role ? 1 : 0

  policy_name = "${var.name}-alibabaeci-policy"
  description = "Read-only ECI discovery for the Traefik Hub alibabaECI provider"

  policy_document = jsonencode({
    Statement = [
      {
        Action   = ["eci:Describe*"]
        Effect   = "Allow"
        Resource = ["*"]
      }
    ]
    Version = "1"
  })
}

resource "alicloud_ram_role_policy_attachment" "traefik" {
  count = var.enable_ram_role ? 1 : 0

  role_name   = alicloud_ram_role.traefik[0].role_name
  policy_name = alicloud_ram_policy.traefik[0].policy_name
  policy_type = "Custom"
}

resource "alicloud_eci_container_group" "traefik" {
  container_group_name = var.name
  restart_policy       = "Always"

  # Private vswitch IP — the parent dials https://<ip>:9443 in-VPC.
  vswitch_id        = var.vswitch_id
  security_group_id = var.security_group_id

  cpu    = var.container_cpu
  memory = var.container_memory

  # The metadata-served credential the provider's default chain ends on.
  ram_role_name = var.enable_ram_role ? alicloud_ram_role.traefik[0].role_name : null

  containers {
    name     = "traefik"
    image    = local.traefik_image
    commands = ["/traefik-hub"]
    args     = local.arguments

    dynamic "ports" {
      for_each = toset(local.exposed_ports)
      content {
        port     = ports.value
        protocol = "TCP"
      }
    }

    # The Hub image is scratch (no shell/cloud-init) — a ConfigFileVolume
    # carries the file-provider config, no init sidecar needed (the ACI
    # sibling's secret-volume pattern).
    dynamic "volume_mounts" {
      for_each = var.file_provider_config != "" ? [1] : []
      content {
        name       = "dynamic"
        mount_path = var.file_provider_path
      }
    }
  }

  dynamic "volumes" {
    for_each = var.file_provider_config != "" ? [1] : []
    content {
      name = "dynamic"
      type = "ConfigFileVolume"

      config_file_volume_config_file_to_paths {
        path    = "dynamic.yml"
        content = base64encode(var.file_provider_config)
      }
    }
  }

  tags = local.discovery_tags
}

# =============================================================================
# Shared Configuration Module - Alibaba ECI
# =============================================================================
# Alibaba ECI uses extracted config from helm template (extract_config=true),
# exactly like ACI/OCI CI. Shared variables are defined here alongside the
# module instantiation.
# =============================================================================

module "config" {
  source = "../shared"

  # Extract config - the container group needs CLI args from Helm template
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
  custom_arguments     = concat(var.custom_arguments, local.alibabaeci_provider_args)
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
