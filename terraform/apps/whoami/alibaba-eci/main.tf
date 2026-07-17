# whoami on Alibaba Cloud ECI (Elastic Container Instance) — the Alibaba
# sibling of apps/whoami/aci and apps/whoami/oci-ci. Each app replica is one
# container group with a private vswitch IP; its TAGS (dotted keys, exactly
# like ACI/OCI tags) are the workload config a Traefik Hub alibabaECI provider
# (traefik/alibaba-eci) discovers.
#
# The declared container port (from apps.<name>.port, default 80) is the
# alibabaECI provider's last-resort backend port when no port tag is set and
# portDiscovery picks the lowest declared container port.
#
# The container group itself is owned by the shared compute/alibaba/eci module
# (the same one traefik/alibaba-eci composes); this module only renders the
# per-replica whoami container spec + tags and hands them over.

locals {
  # A tag is a `:` in the LAST path segment (a registry host may carry a :port).
  image_last_segment = element(split("/", var.whoami_image), length(split("/", var.whoami_image)) - 1)
  image              = length(regexall(":", local.image_last_segment)) > 0 ? var.whoami_image : "${var.whoami_image}:${var.whoami_version}"

  # Same instance-key scheme as the ec2/aci/oci-ci siblings: "<app>-<replica>".
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
}

module "compute" {
  source = "../../../compute/alibaba/eci"

  # Private vswitch IP — the Traefik child dials it in-VPC (ipMode=private).
  vswitch_id        = var.vswitch_id
  security_group_id = var.security_group_id

  groups = {
    for key, grp in local.groups_map : key => {
      cpu    = var.container_cpu
      memory = var.container_memory

      containers = [{
        name  = "whoami"
        image = local.image

        # The declared container port doubles as the alibabaECI provider's
        # portDiscovery fallback when no traefik.*.loadbalancer.server.port tag
        # is set (lowest declared port).
        ports = [{ port = grp.port, protocol = "TCP" }]

        # Built-ins first so module/per-app env can override them.
        environment_vars = merge(
          {
            # WHOAMI_NAME -> body shows `Name: <name>` (e.g. whoami-alibaba-eci).
            WHOAMI_NAME        = grp.name
            WHOAMI_PORT_NUMBER = tostring(grp.port)
          },
          var.environment,
          grp.environment,
        )
      }]

      # Dotted-key traefik.* tags — the alibabaECI provider's workload config,
      # exactly like ACI tags / ECS docker labels.
      tags = merge(var.common_tags, grp.tags)
    }
  }
}
