# whoami on Azure Container Instances — the ACI sibling of apps/whoami/ecs.
# Each app replica is one container group with a private, vnet-injected IP;
# its Azure TAGS (dotted keys, exactly like ECS docker labels) are what a
# Traefik Hub aci provider discovers. The provided subnet MUST be delegated to
# Microsoft.ContainerInstance (compute/azure/vnet's aci_subnet_id already is).

locals {
  # A tag is a `:` in the LAST path segment (a registry host may carry a :port).
  image_last_segment = element(split("/", var.whoami_image), length(split("/", var.whoami_image)) - 1)
  image              = length(regexall(":", local.image_last_segment)) > 0 ? var.whoami_image : "${var.whoami_image}:${var.whoami_version}"

  # Same instance-key scheme as the ec2/azure-vm siblings: "<app>-<replica>".
  groups = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key         = "${app_name}-${replica_idx + 1}"
        app_name    = app_name
        port        = try(app_config.port, 80)
        name        = try(app_config.name, app_name)
        environment = try(app_config.environment, {})
        tags        = try(app_config.tags, {})
      }
    ]
  ])

  groups_map = { for grp in local.groups : grp.key => grp }

  subnet_id = var.create_vnet ? module.vnet[0].aci_subnet_id : var.subnet_id

  # Gate the container on its own exporter's destination. THIS is the leg that has
  # been missing from the unified-ingress service map: whoami-vm reports (the
  # cloud-init snippet waits for the collector on first boot) while whoami-container
  # does not, because a scratch image on ACI had no equivalent and the fork's OTel
  # SDK never recovers from a startup export against a dead endpoint.
  #
  # Read off the exporter env the caller already sets, so the gated endpoint and the
  # exported-to endpoint are the same string by construction and cannot drift. A
  # caller that ships no OTLP config gets no gate and no init container.
  otlp_gate_address = try(var.environment["OTEL_EXPORTER_OTLP_ENDPOINT"], "")
}

# Escape hatch mirroring the azure-vm sibling — off by default; these
# container groups normally join the demo's existing (delegated) subnet.
module "vnet" {
  count  = var.create_vnet ? 1 : 0
  source = "../../../compute/azure/vnet"

  name                = "whoami-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# The container groups themselves live in the shared compute module (composed by
# traefik/aci too). This module keeps the whoami-specific bits — the image tag
# inference, the per-app replica expansion, the WHOAMI_* env, the discovery tags —
# and hands the compute module one entry per replica.
module "compute" {
  source = "../../../compute/azure/aci"

  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = local.subnet_id

  container_name   = "whoami"
  image            = local.image
  container_cpu    = var.container_cpu
  container_memory = var.container_memory

  # whoami's OTLP access logs are gated on --verbose (flag only, no env);
  # every other compute passes it (k8s args, VM ExecStart). ACI `commands`
  # replaces the image ENTRYPOINT wholesale, so the binary path leads.
  commands = ["/whoami", "--verbose"]

  # Do not let the exporter make its first export until the collector answers one.
  otlp_gate_address = local.otlp_gate_address

  # Dotted-key traefik.* tags — the aci provider's workload config,
  # exactly like ECS docker labels.
  common_tags = var.common_tags

  container_groups = {
    for key, grp in local.groups_map : key => {
      # The declared exposed port doubles as the aci provider's fallback when no
      # traefik.*.loadbalancer.server.port tag is set (lowest declared port).
      ports = [grp.port]

      # Built-ins first so module/per-app env can override them.
      environment_variables = merge(
        {
          # WHOAMI_NAME -> body shows `Name: <name>` (e.g. whoami-aci).
          WHOAMI_NAME        = grp.name
          WHOAMI_PORT_NUMBER = tostring(grp.port)
        },
        var.environment,
        grp.environment,
      )

      tags = grp.tags
    }
  }
}
