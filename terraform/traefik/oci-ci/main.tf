# =============================================================================
# OCI CI Traefik Deployment — the multicluster CHILD on OCI Container Instances
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template), exactly like
# traefik/aci. The child IS a container instance running the Hub image with the
# hub.providers.ociContainerInstances provider enabled; the parent dials the
# instance's private VNIC IP on :9443.
#
# AUTH — the default is RESOURCE principals (useResourcePrincipal=true), the
# credential container instances actually inject: keyless, backed by a dynamic
# group + policy this module creates (enable_resource_principal, needs
# tenancy_id — dynamic groups are tenancy-level). Container instances do NOT
# provide the IMDS instance-principal flow (use_instance_principal is kept
# only as an escape hatch; the gateway rejects combining the two flags). With
# the toggle off, auth falls back to CONFIG-FILE: an ~/.oci style config + API
# key delivered as a CONFIGFILE volume (the ACI sibling's secret-volume
# mechanism).
# =============================================================================

locals {
  # Default the provider's discovery scope to the instance's own compartment.
  provider_compartment = coalesce(var.ocici_provider.compartment_id, var.compartment_id)

  # Directory the OCI config/key volume mounts at, derived from the configured
  # config-file path.
  oci_config_dir = dirname(var.ocici_provider.config_file_path)

  # The config-file volume only rides along when it's the active auth path
  # (see the header note) — resource principal is keyless, no secret to mount.
  mount_oci_config = !var.enable_resource_principal && var.oci_config != ""

  # hub.providers.ociContainerInstances static config as CLI flags (same
  # delivery as the aci flags in traefik/aci).
  ocici_provider_args = var.ocici_provider.enabled ? concat(
    [
      "--hub.providers.ociContainerInstances=true",
      "--hub.providers.ociContainerInstances.compartmentID=${local.provider_compartment}",
      "--hub.providers.ociContainerInstances.ipMode=${var.ocici_provider.ip_mode}",
      "--hub.providers.ociContainerInstances.exposedByDefault=${var.ocici_provider.exposed_by_default}",
    ],
    # Exactly one auth flag (see the header note): resource principal (the
    # keyless default) > instance principal (escape hatch — a precondition
    # keeps the two toggles mutually exclusive, the gateway rejects the
    # combination) > the config-file volume.
    var.enable_resource_principal ? ["--hub.providers.ociContainerInstances.useResourcePrincipal=true"] : (
      var.ocici_provider.use_instance_principal ? ["--hub.providers.ociContainerInstances.useInstancePrincipal=true"] : (
        var.oci_config != "" ? ["--hub.providers.ociContainerInstances.configFilePath=${var.ocici_provider.config_file_path}"] : []
      )
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

# The ocici provider's keyless credential: resource principals via a dynamic
# group matching every container instance in the compartment plus a read-only
# policy (the same shape as security/oci-instance-principal for VMs). Dynamic
# groups are tenancy-level, hence tenancy_id; both are named off var.name so
# two instantiations don't collide — same-name instantiations still do.
# OCI IAM is tenancy-level and only writable against the tenancy HOME region
# (var.home_region), while the demo's default OCI provider targets the workload
# region. The dynamic group must additionally live in the tenancy ROOT
# compartment. Both constraints are met by creating the group + policy via the
# OCI CLI (local-exec) against the home region and tenancy root; idempotent
# create, destroy removes by looked-up OCID. (Mirrors security/oci-instance-principal.)
locals {
  rp_name          = "${var.name}-resource-principal"
  rp_matching_rule = "ALL {resource.type='computecontainerinstance', resource.compartment.id='${var.compartment_id}'}"
}

resource "null_resource" "resource_principal_dynamic_group" {
  count = var.enable_resource_principal ? 1 : 0

  triggers = {
    name        = local.rp_name
    home_region = var.home_region
    tenancy     = var.tenancy_id
    rule        = local.rp_matching_rule
  }

  lifecycle {
    precondition {
      condition     = var.tenancy_id != "" && var.home_region != ""
      error_message = "tenancy_id and home_region are required when enable_resource_principal = true (dynamic groups are tenancy-level; IAM writes go to the home region)."
    }
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      existing=$(oci iam dynamic-group list --region ${var.home_region} --compartment-id ${var.tenancy_id} --all --query "data[?name=='${local.rp_name}'].id | [0]" --raw-output 2>/dev/null || true)
      if [ -z "$existing" ] || [ "$existing" = "null" ]; then
        oci iam dynamic-group create --region ${var.home_region} --compartment-id ${var.tenancy_id} \
          --name '${local.rp_name}' --description 'Resource principal for the ${var.name} container instance (ociContainerInstances discovery)' \
          --matching-rule "${local.rp_matching_rule}" --wait-for-state ACTIVE
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -eu
      id=$(oci iam dynamic-group list --region ${self.triggers.home_region} --compartment-id ${self.triggers.tenancy} --all --query "data[?name=='${self.triggers.name}'].id | [0]" --raw-output 2>/dev/null || true)
      if [ -n "$id" ] && [ "$id" != "null" ]; then
        oci iam dynamic-group delete --region ${self.triggers.home_region} --dynamic-group-id "$id" --force
      fi
    EOT
  }
}

# Read-only: exactly what the ocici provider needs — list container instances
# + read their VNIC IPs, nothing else.
resource "null_resource" "resource_principal_policy" {
  count      = var.enable_resource_principal ? 1 : 0
  depends_on = [null_resource.resource_principal_dynamic_group]

  triggers = {
    name        = local.rp_name
    home_region = var.home_region
    tenancy     = var.tenancy_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      existing=$(oci iam policy list --region ${var.home_region} --compartment-id ${var.tenancy_id} --all --query "data[?name=='${local.rp_name}'].id | [0]" --raw-output 2>/dev/null || true)
      if [ -z "$existing" ] || [ "$existing" = "null" ]; then
        oci iam policy create --region ${var.home_region} --compartment-id ${var.tenancy_id} \
          --name '${local.rp_name}' --description 'Resource principal policy for the ${var.name} container instance' \
          --statements '["Allow dynamic-group ${local.rp_name} to read compute-container-family in compartment id ${var.compartment_id}", "Allow dynamic-group ${local.rp_name} to read virtual-network-family in compartment id ${var.compartment_id}"]' \
          --wait-for-state ACTIVE
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -eu
      id=$(oci iam policy list --region ${self.triggers.home_region} --compartment-id ${self.triggers.tenancy} --all --query "data[?name=='${self.triggers.name}'].id | [0]" --raw-output 2>/dev/null || true)
      if [ -n "$id" ] && [ "$id" != "null" ]; then
        oci iam policy delete --region ${self.triggers.home_region} --policy-id "$id" --force
      fi
    EOT
  }
}

resource "oci_container_instances_container_instance" "traefik" {
  availability_domain      = local.availability_domain
  compartment_id           = var.compartment_id
  display_name             = var.name
  shape                    = var.shape
  container_restart_policy = "ALWAYS"

  lifecycle {
    precondition {
      condition     = !(var.enable_resource_principal && var.ocici_provider.use_instance_principal)
      error_message = "enable_resource_principal and ocici_provider.use_instance_principal are mutually exclusive — the gateway rejects combining useResourcePrincipal with useInstancePrincipal."
    }

    precondition {
      condition     = var.enable_resource_principal || var.ocici_provider.use_instance_principal || !var.ocici_provider.enabled || (var.oci_config != "" && var.oci_private_key != "")
      error_message = "oci_config and oci_private_key are required when enable_resource_principal = false (the ocici provider's config-file credential)."
    }
  }

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
      for_each = local.mount_oci_config ? [1] : []
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
    for_each = local.mount_oci_config ? [1] : []
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
