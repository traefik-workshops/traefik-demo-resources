# whoami on IBM Cloud VPC virtual server instances — the IBM sibling of
# apps/whoami/ec2 and apps/whoami/alibaba-ecs. Reuses the whoami/cloud-init
# template (docker-run systemd unit); each app replica is one small VSI.
#
# DIFFERENT DISCOVERY MODEL from every other VM sibling: IBM user tags are
# flat strings with a restricted character set, so they CANNOT carry dotted
# traefik.* configuration the way EC2/Azure/OCI/Alibaba tags do. The Hub
# ibmVPC provider (traefik/ibm-vpc) instead reads a base configuration FILE
# for routers/services/middlewares, and each instance carries exactly one
# assignment tag "<service_name_tag_key>:<service_name>" that adds its IP to
# that service's servers. `service_name` per app is therefore the ONLY
# traefik-facing input here.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-ibm-vpc).
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

data "ibm_is_subnet" "selected" {
  identifier = var.subnet_id
}

# Latest stock Ubuntu 24.04 amd64 image — the same OS the ec2/alibaba-ecs
# siblings run (the whoami cloud-init installs docker via apt). IBM has no
# server-side name wildcard, so filter the public catalog locally.
data "ibm_is_images" "ubuntu" {
  count = var.image_id != "" ? 0 : 1

  status     = "available"
  visibility = "public"
}

locals {
  ubuntu_image_names = var.image_id != "" ? [] : sort([
    for img in data.ibm_is_images.ubuntu[0].images :
    img.name if can(regex("^ibm-ubuntu-24-04(-\\d+)?-minimal-amd64", img.name))
  ])

  image_id = var.image_id != "" ? var.image_id : [
    for img in data.ibm_is_images.ubuntu[0].images :
    img.id if img.name == element(local.ubuntu_image_names, length(local.ubuntu_image_names) - 1)
  ][0]

  # Replicate the ec2/alibaba-ecs siblings' instance-key scheme: "<app>-<replica>".
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key      = "${app_name}-${replica_idx + 1}"
        app_name = app_name
        # The service this instance joins in the ibmVPC provider's base
        # configuration file. Defaults to the app's key.
        service_name = try(app_config.service_name, app_name)
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }
}

resource "ibm_is_instance" "whoami" {
  for_each = local.instances_map

  name    = each.key
  image   = local.image_id
  profile = var.instance_profile

  vpc            = data.ibm_is_subnet.selected.vpc
  zone           = data.ibm_is_subnet.selected.zone
  resource_group = var.resource_group_id != "" ? var.resource_group_id : null
  keys           = var.ssh_key_ids

  primary_network_interface {
    subnet          = var.subnet_id
    security_groups = var.security_group_ids
  }

  # IBM takes cloud-init user data as plain text (no base64).
  user_data = module.cloud_init[each.value.app_name].rendered

  # The single assignment tag the ibmVPC provider's Global Search query
  # resolves — a flat "<key>:<service>" string, NOT a dotted traefik.* tag.
  # IBM stores user tags lowercased; keep service names lowercase.
  tags = concat(var.common_tags, ["${var.service_name_tag_key}:${each.value.service_name}"])
}

# Inbound-only convenience: egress for image pulls comes from the subnet's
# public gateway (compute/ibm/vpc attaches one per zone), not from these.
resource "ibm_is_floating_ip" "whoami" {
  for_each = var.enable_floating_ip ? local.instances_map : {}

  name   = "${each.key}-fip"
  target = ibm_is_instance.whoami[each.key].primary_network_interface[0].id
}
