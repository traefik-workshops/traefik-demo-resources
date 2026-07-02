# Demo VPC mirroring compute/azure/vnet: one VPC, two vswitches spread across
# the region's first two zones (ECS VMs, ECI container groups and ACK nodes
# can all share them — Alibaba needs no subnet delegation), and a security
# group opening the same demo ports as the Azure NSG (80/443/8080/22 +
# extra_ingress_ports). Unlike Azure NSGs, Alibaba security groups attach to
# instances/container groups, not subnets — pass security_group_id to the
# workloads that join the vswitches.

data "alicloud_zones" "demo" {
  available_resource_creation = "VSwitch"
}

resource "alicloud_vpc" "demo" {
  vpc_name   = var.name
  cidr_block = var.cidr
}

resource "alicloud_vswitch" "demo" {
  count = length(var.vswitch_cidrs)

  vswitch_name = "${var.name}-vswitch-${count.index + 1}"
  vpc_id       = alicloud_vpc.demo.id
  cidr_block   = var.vswitch_cidrs[count.index]
  # Spread across zones (wrapping when there are fewer zones than vswitches)
  # so ACK control planes / node pools can consume them directly.
  zone_id = data.alicloud_zones.demo.zones[count.index % length(data.alicloud_zones.demo.zones)].id
}

locals {
  # Public-facing demo ports (any source) + extra ports opened intra-VPC only
  # (e.g. the Hub multicluster uplink :9443 on ECS/ECI spokes the parent
  # cluster dials).
  ingress_rules = merge(
    {
      http  = { port = 80, cidr = "0.0.0.0/0" }
      https = { port = 443, cidr = "0.0.0.0/0" }
      alt   = { port = 8080, cidr = "0.0.0.0/0" }
      ssh   = { port = 22, cidr = "0.0.0.0/0" }
    },
    {
      for port in var.extra_ingress_ports :
      "extra-${port}" => { port = port, cidr = var.cidr }
    }
  )
}

resource "alicloud_security_group" "demo" {
  security_group_name = "${var.name}-sg"
  vpc_id              = alicloud_vpc.demo.id
}

resource "alicloud_security_group_rule" "ingress" {
  for_each = local.ingress_rules

  type              = "ingress"
  ip_protocol       = "tcp"
  policy            = "accept"
  port_range        = "${each.value.port}/${each.value.port}"
  cidr_ip           = each.value.cidr
  security_group_id = alicloud_security_group.demo.id
}
