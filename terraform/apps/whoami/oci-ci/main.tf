# whoami on OCI Container Instances — the OCI sibling of apps/whoami/aci.
# Each app replica is one container instance with a private VNIC IP; its
# FREEFORM TAGS (dotted keys, exactly like ACI tags / ECS docker labels) are
# the workload config a Traefik Hub ociContainerInstances provider
# (traefik/oci-ci) discovers.
#
# OCI container instances have no "published port" field, so the declared
# port rides the container's TCP HEALTH CHECK — the ocici provider's
# last-resort backend port when no port tag is set and NSG discovery is off.

locals {
  # A tag is a `:` in the LAST path segment (a registry host may carry a :port).
  image_last_segment = element(split("/", var.whoami_image), length(split("/", var.whoami_image)) - 1)
  image              = length(regexall(":", local.image_last_segment)) > 0 ? var.whoami_image : "${var.whoami_image}:${var.whoami_version}"

  # Same instance-key scheme as the ec2/aci siblings: "<app>-<replica>".
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

# The container instances themselves live in the shared compute/oracle/ci module.
# This caller renders each replica's whoami container (image, env, health check)
# and dotted-key freeform tags — its role logic — and hands them in as the opaque
# per-instance payload; the module owns the resource, the AD pick and the VNIC
# private-IP resolution.
module "ci" {
  source = "../../../compute/oracle/ci"

  compartment_id          = var.compartment_id
  availability_domain     = var.availability_domain
  subnet_id               = var.subnet_id
  nsg_ids                 = var.nsg_ids
  shape                   = var.shape
  container_ocpus         = var.container_ocpus
  container_memory_in_gbs = var.container_memory_in_gbs

  instances = {
    for key, grp in local.groups_map : key => {
      display_name = key

      # Dotted-key traefik.* freeform tags — the ociContainerInstances provider's
      # workload config, exactly like ACI tags / ECS docker labels.
      freeform_tags = merge(var.common_tags, grp.tags)

      containers = [{
        display_name = "whoami"
        image_url    = local.image

        # Built-ins first so module/per-app env can override them.
        environment_variables = merge(
          {
            # WHOAMI_NAME -> body shows `Name: <name>` (e.g. whoami-oci-ci).
            WHOAMI_NAME        = grp.name
            WHOAMI_PORT_NUMBER = tostring(grp.port)
          },
          var.environment,
          grp.environment,
        )

        # The health-check port doubles as the declared container port the ocici
        # provider falls back to when no traefik.*.loadbalancer.server.port tag is
        # set (lowest declared port).
        health_checks = {
          health_check_type = "TCP"
          port              = grp.port
        }
      }]
    }
  }
}
