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

# One shared ECS fleet per app — keyed "<app>-1 .. <app>-N" (the same scheme as
# the ec2/azure-vm/oci-vm siblings). Every replica of an app shares that app's
# rendered cloud-init and its dotted-key traefik.* tags (the alibabaECS
# provider's workload config). The instance, its Ubuntu image lookup and the
# public-IP bandwidth trick now live in compute/alibaba/ecs.
module "compute" {
  for_each = var.apps
  source   = "../../../compute/alibaba/ecs"

  name     = each.key
  replicas = each.value.replicas

  instance_type        = var.instance_type
  image_id             = var.image_id
  vswitch_id           = var.vswitch_id
  security_group_ids   = var.security_group_ids
  system_disk_category = var.system_disk_category
  system_disk_size     = var.system_disk_size
  enable_public_ip     = var.enable_public_ip

  user_data = module.cloud_init[each.key].rendered

  tags = merge(var.common_tags, try(each.value.tags, {}))
}
