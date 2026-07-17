# =============================================================================
# compute/oracle/ci — the shared OCI Container Instance resource
# =============================================================================
# Extracted verbatim from traefik/oci-ci and apps/whoami/oci-ci (they each used
# to create this same resource). The AD pick and the VNIC private-IP resolution
# also live here so both callers stop duplicating them.
# =============================================================================

data "oci_identity_availability_domains" "this" {
  compartment_id = var.compartment_id
}

locals {
  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.this.availability_domains[0].name
}

resource "oci_container_instances_container_instance" "this" {
  for_each = var.instances

  availability_domain      = local.availability_domain
  compartment_id           = var.compartment_id
  display_name             = each.value.display_name
  shape                    = var.shape
  container_restart_policy = "ALWAYS"

  shape_config {
    ocpus         = var.container_ocpus
    memory_in_gbs = var.container_memory_in_gbs
  }

  # Private VNIC: the parent dials the instance's PRIVATE IP in-VCN, and egress
  # (image pull) goes through the node subnet's NAT gateway — so no public IP is
  # needed by default.
  vnics {
    subnet_id             = var.subnet_id
    is_public_ip_assigned = var.enable_public_ip
    nsg_ids               = var.nsg_ids
    private_ip            = each.value.private_ip
  }

  dynamic "containers" {
    for_each = each.value.containers
    content {
      display_name          = containers.value.display_name
      image_url             = containers.value.image_url
      command               = containers.value.command
      arguments             = containers.value.arguments
      environment_variables = containers.value.environment_variables

      dynamic "health_checks" {
        for_each = containers.value.health_checks != null ? [containers.value.health_checks] : []
        content {
          health_check_type = health_checks.value.health_check_type
          port              = health_checks.value.port
        }
      }

      dynamic "volume_mounts" {
        for_each = containers.value.volume_mounts
        content {
          volume_name = volume_mounts.value.volume_name
          mount_path  = volume_mounts.value.mount_path
        }
      }
    }
  }

  dynamic "volumes" {
    for_each = each.value.volumes
    content {
      name        = volumes.value.name
      volume_type = volumes.value.volume_type

      dynamic "configs" {
        for_each = volumes.value.configs
        content {
          file_name = configs.value.file_name
          data      = configs.value.data
        }
      }
    }
  }

  freeform_tags = each.value.freeform_tags
}

# The container instance resource only exposes the VNIC OCID; the private IP
# comes from the VNIC itself.
data "oci_core_vnic" "this" {
  for_each = var.instances

  vnic_id = oci_container_instances_container_instance.this[each.key].vnics[0].vnic_id
}
