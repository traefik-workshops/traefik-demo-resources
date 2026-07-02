# whoami on OCI Compute VMs — the OCI sibling of apps/whoami/ec2 and
# apps/whoami/azure-vm. Reuses the whoami/cloud-init template (docker-run
# systemd unit); each app replica is one small VM whose FREEFORM TAGS (dotted
# keys, exactly like EC2/Azure tags) are the workload config a Traefik Hub
# oci provider (traefik/oci-vm) discovers.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-oci-vm).
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

data "oci_identity_availability_domains" "whoami" {
  compartment_id = var.compartment_id
}

# Latest Canonical Ubuntu 24.04 platform image for the chosen shape — the same
# OS the azure-vm/gce siblings run (the whoami cloud-init installs docker via
# apt, which Oracle Linux doesn't ship).
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  # Replicate the ec2/azure-vm siblings' instance-key scheme: "<app>-<replica>".
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key      = "${app_name}-${replica_idx + 1}"
        app_name = app_name
        tags     = try(app_config.tags, {})
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }

  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.whoami.availability_domains[0].name
  image_id            = var.vm_image_ocid != "" ? var.vm_image_ocid : data.oci_core_images.ubuntu.images[0].id
}

resource "oci_core_instance" "whoami" {
  for_each = local.instances_map

  availability_domain = local.availability_domain
  compartment_id      = var.compartment_id
  display_name        = each.key
  shape               = var.shape

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = var.enable_public_ip
    nsg_ids          = var.nsg_ids
  }

  source_details {
    source_type = "image"
    source_id   = local.image_id
  }

  metadata = {
    user_data = base64encode(module.cloud_init[each.value.app_name].rendered)
  }

  # Dotted-key traefik.* freeform tags — the oci provider's workload config,
  # exactly like EC2 instance tags.
  freeform_tags = merge(var.common_tags, each.value.tags)
}
