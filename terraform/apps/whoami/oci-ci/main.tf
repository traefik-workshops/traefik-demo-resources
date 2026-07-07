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

  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.whoami.availability_domains[0].name
}

data "oci_identity_availability_domains" "whoami" {
  compartment_id = var.compartment_id
}

resource "oci_container_instances_container_instance" "whoami" {
  for_each = local.groups_map

  availability_domain      = local.availability_domain
  compartment_id           = var.compartment_id
  display_name             = each.key
  shape                    = var.shape
  container_restart_policy = "ALWAYS"

  shape_config {
    ocpus         = var.container_ocpus
    memory_in_gbs = var.container_memory_in_gbs
  }

  # Dual IP: the Traefik child dials the PRIVATE VNIC IP in-VCN (ipMode=private),
  # while the public IP is needed for egress — the OKE VCN routes through an
  # internet gateway (not a NAT gateway), so a private-only container instance
  # can't pull its image ("inadequate network configuration"). OKE nodes + the
  # whoami VMs are public for the same reason.
  vnics {
    subnet_id             = var.subnet_id
    is_public_ip_assigned = true
    nsg_ids               = var.nsg_ids
  }

  containers {
    display_name = "whoami"
    image_url    = local.image

    # Built-ins first so module/per-app env can override them.
    environment_variables = merge(
      {
        # WHOAMI_NAME -> body shows `Name: <name>` (e.g. whoami-oci-ci).
        WHOAMI_NAME        = each.value.name
        WHOAMI_PORT_NUMBER = tostring(each.value.port)
      },
      var.environment,
      each.value.environment,
    )

    # The health-check port doubles as the declared container port the ocici
    # provider falls back to when no traefik.*.loadbalancer.server.port tag is
    # set (lowest declared port).
    health_checks {
      health_check_type = "TCP"
      port              = each.value.port
    }
  }

  # Dotted-key traefik.* freeform tags — the ociContainerInstances provider's
  # workload config, exactly like ACI tags / ECS docker labels.
  freeform_tags = merge(var.common_tags, each.value.tags)
}

# The container instance resource only exposes the VNIC OCID; the private IP
# comes from the VNIC itself.
data "oci_core_vnic" "whoami" {
  for_each = local.groups_map

  vnic_id = oci_container_instances_container_instance.whoami[each.key].vnics[0].vnic_id
}
