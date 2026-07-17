# =============================================================================
# compute/alibaba/ecs — the shared Alibaba Cloud ECS instance fleet
# =============================================================================
# Owns the alicloud_instance the Traefik gateway (traefik/alibaba-ecs) and the
# whoami backend (apps/whoami/alibaba-ecs) both create today. Takes a
# fully-rendered user_data string as an OPAQUE input — no role-specific
# (Hub / whoami) logic and no cloud-init generation live here. The optional
# module-created security group mirrors the gateway's old enable_security_group
# escape hatch; the private_ip pin is preserved as the per-index private_ips
# list.
# =============================================================================

# Latest Ubuntu 24.04 public image — the same OS the ec2/azure-vm/oci-vm
# siblings run (the cloud-init installs docker via apt).
data "alicloud_images" "ubuntu" {
  owners      = "system"
  name_regex  = "^ubuntu_24_04_x64"
  most_recent = true
}

locals {
  image_id = var.image_id != "" ? var.image_id : data.alicloud_images.ubuntu.images[0].id

  # Replicate the ec2/azure-vm/oci-vm siblings' instance-key scheme: "<name>-<index>".
  instances_map = {
    for idx in range(var.replicas) :
    "${var.name}-${idx + var.replica_start_index}" => {
      idx = idx
    }
  }
}

# Escape hatch mirroring traefik/oci-vm's enable_nsg: a security group opening
# the demo ports (incl. the :9443 uplink the parent dials) from
# security_group_source_cidr. Off by default — compute/alibaba/vpc's group
# already opens them.
resource "alicloud_security_group" "this" {
  count = var.enable_security_group ? 1 : 0

  security_group_name = "${var.name}-sg"
  vpc_id              = var.vpc_id
}

resource "alicloud_security_group_rule" "ingress" {
  for_each = var.enable_security_group ? { for port in var.security_group_ingress_ports : tostring(port) => port } : {}

  type              = "ingress"
  ip_protocol       = "tcp"
  policy            = "accept"
  port_range        = "${each.value}/${each.value}"
  cidr_ip           = var.security_group_source_cidr
  security_group_id = alicloud_security_group.this[0].id
}

resource "alicloud_instance" "ecs" {
  for_each = local.instances_map

  instance_name   = each.key
  instance_type   = var.instance_type
  image_id        = local.image_id
  vswitch_id      = var.vswitch_id
  private_ip      = try(var.private_ips[each.value.idx], null)
  security_groups = concat(var.security_group_ids, var.enable_security_group ? [alicloud_security_group.this[0].id] : [])

  system_disk_category = var.system_disk_category
  system_disk_size     = var.system_disk_size

  # internet_max_bandwidth_out > 0 is what allocates a public IP on Alibaba.
  internet_max_bandwidth_out = var.enable_public_ip ? 10 : 0

  user_data = base64encode(var.user_data)

  tags = var.tags
}
