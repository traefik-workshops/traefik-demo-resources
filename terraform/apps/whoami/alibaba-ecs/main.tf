# whoami on Alibaba Cloud ECS instances — the Alibaba sibling of
# apps/whoami/ec2, apps/whoami/azure-vm and apps/whoami/oci-vm. Reuses the
# whoami/cloud-init template (docker-run systemd unit); each app replica is
# one small ECS instance whose TAGS (dotted keys, exactly like EC2/Azure/OCI
# tags) are the workload config a Traefik Hub alibabaECS provider
# (traefik/alibaba-ecs) discovers.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-alibaba-ecs).
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

# Latest Ubuntu 24.04 public image — the same OS the ec2/azure-vm/oci-vm
# siblings run (the whoami cloud-init installs docker via apt).
data "alicloud_images" "ubuntu" {
  owners      = "system"
  name_regex  = "^ubuntu_24_04_x64"
  most_recent = true
}

locals {
  # Replicate the ec2/azure-vm/oci-vm siblings' instance-key scheme: "<app>-<replica>".
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

  image_id = var.image_id != "" ? var.image_id : data.alicloud_images.ubuntu.images[0].id
}

resource "alicloud_instance" "whoami" {
  for_each = local.instances_map

  instance_name   = each.key
  instance_type   = var.instance_type
  image_id        = local.image_id
  vswitch_id      = var.vswitch_id
  security_groups = var.security_group_ids

  system_disk_category = var.system_disk_category
  system_disk_size     = var.system_disk_size

  # internet_max_bandwidth_out > 0 is what allocates a public IP on Alibaba;
  # docker pulls need outbound internet (public IP or a NAT gateway on the
  # vswitch, e.g. compute/alibaba/ack's enable_nat_gateway).
  internet_max_bandwidth_out = var.enable_public_ip ? 10 : 0

  user_data = base64encode(module.cloud_init[each.value.app_name].rendered)

  # Dotted-key traefik.* tags — the alibabaECS provider's workload config,
  # exactly like EC2 instance tags.
  tags = merge(var.common_tags, each.value.tags)
}
