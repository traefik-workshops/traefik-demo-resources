# =============================================================================
# ACI Traefik Deployment — the multicluster CHILD on Azure Container Instances
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template), exactly like
# traefik/ecs. The child IS a container group running the Hub image with the
# hub.providers.aci provider enabled; a system-assigned managed identity +
# Reader on the resource group is its discovery credential; the parent dials
# the group's private vnet-injected IP on :9443.
# =============================================================================

data "azurerm_client_config" "current" {}

locals {
  subscription_id = coalesce(var.aci_provider.subscription_id, data.azurerm_client_config.current.subscription_id)
  # Default the provider's discovery scope to the container group's own resource group.
  provider_resource_group = coalesce(var.aci_provider.resource_group, var.resource_group_name)

  # hub.providers.aci static config as CLI flags (same delivery as the ECS
  # demo's custom_arguments). No tenantID/clientID/clientSecret:
  # DefaultAzureCredential resolves the group's system-assigned identity.
  aci_provider_args = var.aci_provider.enabled ? concat(
    [
      "--hub.providers.aci=true",
      "--hub.providers.aci.subscriptionID=${local.subscription_id}",
      "--hub.providers.aci.resourceGroup=${local.provider_resource_group}",
      "--hub.providers.aci.ipMode=${var.aci_provider.ip_mode}",
      "--hub.providers.aci.exposedByDefault=${var.aci_provider.exposed_by_default}",
    ],
    var.aci_provider.default_rule != "" ? ["--hub.providers.aci.defaultRule=${var.aci_provider.default_rule}"] : [],
    var.aci_provider.constraints != "" ? ["--hub.providers.aci.constraints=${var.aci_provider.constraints}"] : [],
    var.aci_provider.refresh_seconds != null ? ["--hub.providers.aci.refreshSeconds=${var.aci_provider.refresh_seconds}"] : [],
    # Without portDiscovery the provider falls back to the container group's
    # lowest declared exposed port when no port tag is set.
    var.aci_provider.port_discovery ? ["--hub.providers.aci.portDiscovery=true"] : [],
  ) : []

  # Use extracted CLI arguments from Helm template
  # Uses centralized filtering to exclude Kubernetes-specific args
  traefik_arguments = module.config.extracted_cli_args_cloud

  # Use shared module for image reference
  traefik_image = module.config.image_full

  # All entrypoint ports plus the uplink :9443 — a private container group
  # must declare every port it serves.
  exposed_ports = distinct(concat(module.config.ports_list, [9443]))

  # The shared module strips --hub.token from the extracted args so it can be
  # injected per-platform. ACI `commands` REPLACES the image entrypoint (unlike
  # ECS `command`, which appends), so the binary path leads; and it's exec'd
  # with no shell, so the token value is inlined rather than read from an env var.
  commands = concat(
    ["/traefik-hub", "--hub.token=${var.traefik_hub_token}"],
    local.traefik_arguments
  )

  # Build Azure tags including ports — the aci provider's workload config,
  # exactly like the ECS task's docker labels.
  discovery_tags = merge(var.extra_tags, {
    for name, port in module.config.ports :
    "traefik.http.routers.${name}.entrypoints" => name
    if try(port.expose.default, false)
    },
    # Self-register the Traefik group's own dashboard via its aci provider
    # (-> dashboard@aci). Disable when the dashboard is advertised another way
    # (e.g. a file-rule uplink): without traefik.enable the group isn't
    # self-discovered at all, so no redundant self-router appears.
    var.enable_dashboard_discovery ? {
      "traefik.enable"                                           = "true"
      "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
      "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
      "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
  } : {})
}

resource "azurerm_container_group" "traefik" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  restart_policy      = "Always"

  # Private vnet-injected IP — the parent dials https://<ip>:9443 in-vnet.
  # The subnet MUST be delegated to Microsoft.ContainerInstance.
  ip_address_type = "Private"
  subnet_ids      = [var.subnet_id]

  # DefaultAzureCredential inside the container resolves this identity via the
  # ACI-injected identity endpoint.
  identity {
    type = "SystemAssigned"
  }

  dynamic "exposed_port" {
    for_each = toset(local.exposed_ports)
    content {
      port     = exposed_port.value
      protocol = "TCP"
    }
  }

  container {
    name     = "traefik"
    image    = local.traefik_image
    cpu      = var.container_cpu
    memory   = var.container_memory
    commands = local.commands

    dynamic "ports" {
      for_each = toset(local.exposed_ports)
      content {
        port     = ports.value
        protocol = "TCP"
      }
    }

    # The Hub image is scratch (no shell/cloud-init) — a secret volume carries
    # the file-provider config, no init sidecar needed (unlike ECS).
    dynamic "volume" {
      for_each = var.file_provider_config != "" ? [1] : []
      content {
        name       = "dynamic"
        mount_path = var.file_provider_path
        secret = {
          "dynamic.yml" = base64encode(var.file_provider_config)
        }
      }
    }
  }

  tags = local.discovery_tags
}

# Reader on the resource group: the least privilege the aci provider needs to
# list container groups in its discovery scope.
resource "azurerm_role_assignment" "reader" {
  count = var.enable_reader_role ? 1 : 0

  scope                = "/subscriptions/${local.subscription_id}/resourceGroups/${local.provider_resource_group}"
  role_definition_name = "Reader"
  principal_id         = azurerm_container_group.traefik.identity[0].principal_id
}

# Identity token race: a freshly-created group's system-assigned identity acquires
# its ARM token BEFORE the Reader assignment above lands (the group must exist for
# its principal_id to exist, so the grant always loses the race on pass 1) — the
# aci provider then 403s on every list call until the group restarts and mints a
# fresh token. Historically masked by a manual `az container restart` during
# validation (azure-unified-ingress 2026-07); this makes the bounce durable. Fires
# ONLY when the group is (re)created — steady-state applies are untouched. The OCI
# analogue is oci-ci's resource_principal_bounce (same race, resource principals).
resource "null_resource" "identity_bounce" {
  count      = var.enable_reader_role ? 1 : 0
  depends_on = [azurerm_role_assignment.reader]

  triggers = {
    container_group_id = azurerm_container_group.traefik.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      # Give RBAC propagation time (regional AAD replication), then force a fresh
      # identity token. `az container restart` blocks until the group is running.
      sleep 120
      az container restart \
        --resource-group ${var.resource_group_name} \
        --name ${var.name}
    EOT
  }
}

# =============================================================================
# Shared Configuration Module - ACI
# =============================================================================
# ACI uses extracted config from helm template (extract_config=true), exactly
# like ECS. Shared variables are defined here alongside the module
# instantiation.
# =============================================================================

module "config" {
  source = "../shared"

  # Extract config - ACI needs CLI args, env vars from Helm template
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
  custom_arguments     = concat(var.custom_arguments, local.aci_provider_args)
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
