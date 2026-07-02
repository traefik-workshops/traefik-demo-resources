# =============================================================================
# OCI CI Traefik Deployment — the multicluster CHILD on OCI Container Instances
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template), exactly like
# traefik/aci. The child IS a container instance running the Hub image with the
# hub.providers.ociContainerInstances provider enabled; the parent dials the
# instance's private VNIC IP on :9443.
#
# AUTH — honest limitation: the ocici provider (like the oci one) implements
# useInstancePrincipal via the OCI SDK's IMDS-backed instance-principal flow,
# which container instances do NOT provide (they inject RESOURCE-principal
# credentials instead, which the provider doesn't consume yet). Until it grows
# resource-principal support, the default here is CONFIG-FILE auth: an ~/.oci
# style config + API key delivered as a CONFIGFILE volume (the ACI sibling's
# secret-volume mechanism), with use_instance_principal exposed as a toggle
# for when the gap closes.
# =============================================================================

locals {
  # Default the provider's discovery scope to the instance's own compartment.
  provider_compartment = coalesce(var.ocici_provider.compartment_id, var.compartment_id)

  # Directory the OCI config/key volume mounts at, derived from the configured
  # config-file path.
  oci_config_dir = dirname(var.ocici_provider.config_file_path)

  # hub.providers.ociContainerInstances static config as CLI flags (same
  # delivery as the aci flags in traefik/aci).
  ocici_provider_args = var.ocici_provider.enabled ? concat(
    [
      "--hub.providers.ociContainerInstances=true",
      "--hub.providers.ociContainerInstances.compartmentID=${local.provider_compartment}",
      "--hub.providers.ociContainerInstances.ipMode=${var.ocici_provider.ip_mode}",
      "--hub.providers.ociContainerInstances.exposedByDefault=${var.ocici_provider.exposed_by_default}",
    ],
    # Instance-principal is a forward-looking toggle (see the header note);
    # the working path today is the config-file volume.
    var.ocici_provider.use_instance_principal ? ["--hub.providers.ociContainerInstances.useInstancePrincipal=true"] : (
      var.oci_config != "" ? ["--hub.providers.ociContainerInstances.configFilePath=${var.ocici_provider.config_file_path}"] : []
    ),
    var.ocici_provider.region != "" ? ["--hub.providers.ociContainerInstances.region=${var.ocici_provider.region}"] : [],
    var.ocici_provider.default_rule != "" ? ["--hub.providers.ociContainerInstances.defaultRule=${var.ocici_provider.default_rule}"] : [],
    var.ocici_provider.constraints != "" ? ["--hub.providers.ociContainerInstances.constraints=${var.ocici_provider.constraints}"] : [],
    var.ocici_provider.refresh_seconds != null ? ["--hub.providers.ociContainerInstances.refreshSeconds=${var.ocici_provider.refresh_seconds}"] : [],
    # Without nsgPortDiscovery the provider falls back to the instance's
    # lowest declared container port (carried by the container health check).
    var.ocici_provider.nsg_port_discovery ? ["--hub.providers.ociContainerInstances.nsgPortDiscovery=true"] : [],
  ) : []

  # Use extracted CLI arguments from Helm template
  # Uses centralized filtering to exclude Kubernetes-specific args
  traefik_arguments = module.config.extracted_cli_args_cloud

  # Use shared module for image reference
  traefik_image = module.config.image_full

  # The shared module strips --hub.token from the extracted args so it can be
  # injected per-platform. OCI `command` REPLACES the image entrypoint (like
  # ACI `commands`) and is exec'd with no shell, so the token value is inlined
  # in `arguments` rather than read from an env var.
  arguments = concat(
    ["--hub.token=${var.traefik_hub_token}"],
    local.traefik_arguments
  )

  # Build freeform tags including ports — the ociContainerInstances provider's
  # workload config, exactly like the ACI group's Azure tags. NOTE: container
  # instances have no "published port" list; reachability of the entrypoints
  # (incl. the :9443 uplink) is governed by the subnet's security lists/NSGs.
  discovery_tags = merge(var.extra_tags, {
    for name, port in module.config.ports :
    "traefik.http.routers.${name}.entrypoints" => name
    if try(port.expose.default, false)
    },
    # Self-register the Traefik instance's own dashboard via its ocici
    # provider (-> dashboard@ocici). Disable when the dashboard is advertised
    # another way (e.g. a file-rule uplink): without traefik.enable the
    # instance isn't self-discovered at all, so no redundant self-router
    # appears.
    var.enable_dashboard_discovery ? {
      "traefik.enable"                                           = "true"
      "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
      "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
      "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
  } : {})

  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.traefik.availability_domains[0].name
}

data "oci_identity_availability_domains" "traefik" {
  compartment_id = var.compartment_id
}

resource "oci_container_instances_container_instance" "traefik" {
  availability_domain      = local.availability_domain
  compartment_id           = var.compartment_id
  display_name             = var.name
  shape                    = var.shape
  container_restart_policy = "ALWAYS"

  shape_config {
    ocpus         = var.container_ocpus
    memory_in_gbs = var.container_memory_in_gbs
  }

  # Private VNIC IP — the parent dials https://<ip>:9443 in-VCN.
  vnics {
    subnet_id             = var.subnet_id
    is_public_ip_assigned = false
    nsg_ids               = var.nsg_ids
  }

  containers {
    display_name = "traefik"
    image_url    = local.traefik_image
    command      = ["/traefik-hub"]
    arguments    = local.arguments

    # The Hub image is scratch (no shell/cloud-init) — CONFIGFILE volumes
    # carry the file-provider config and the OCI credentials, no init sidecar
    # needed (the ACI sibling's secret-volume pattern).
    dynamic "volume_mounts" {
      for_each = var.file_provider_config != "" ? [1] : []
      content {
        volume_name = "dynamic"
        mount_path  = var.file_provider_path
      }
    }

    dynamic "volume_mounts" {
      for_each = var.oci_config != "" ? [1] : []
      content {
        volume_name = "oci-config"
        mount_path  = local.oci_config_dir
      }
    }
  }

  dynamic "volumes" {
    for_each = var.file_provider_config != "" ? [1] : []
    content {
      name        = "dynamic"
      volume_type = "CONFIGFILE"

      configs {
        file_name = "dynamic.yml"
        data      = base64encode(var.file_provider_config)
      }
    }
  }

  # The provider's config-file credential: an ~/.oci style config plus the API
  # private key it references (its key_file must point inside the mount, e.g.
  # <config dir>/key.pem).
  dynamic "volumes" {
    for_each = var.oci_config != "" ? [1] : []
    content {
      name        = "oci-config"
      volume_type = "CONFIGFILE"

      configs {
        file_name = basename(var.ocici_provider.config_file_path)
        data      = base64encode(var.oci_config)
      }

      configs {
        file_name = "key.pem"
        data      = base64encode(var.oci_private_key)
      }
    }
  }

  freeform_tags = local.discovery_tags
}

# The container instance resource only exposes the VNIC OCID; the private IP
# comes from the VNIC itself.
data "oci_core_vnic" "traefik" {
  vnic_id = oci_container_instances_container_instance.traefik.vnics[0].vnic_id
}

# =============================================================================
# Shared Configuration Module - OCI CI
# =============================================================================
# OCI CI uses extracted config from helm template (extract_config=true),
# exactly like ACI/ECS. Shared variables are defined here alongside the module
# instantiation.
# =============================================================================

module "config" {
  source = "../shared"

  # Extract config - the container instance needs CLI args from Helm template
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
  custom_arguments     = concat(var.custom_arguments, local.ocici_provider_args)
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
