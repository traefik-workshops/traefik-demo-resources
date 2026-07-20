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

# Outbound internet for the vswitches. Unlike Azure (default outbound) and AWS (an IGW +
# route), an Alibaba VPC has NO egress until you give it one: without this the ECS/ECI spokes
# boot fine but their image pulls time out ("ensure the VPC network has public network access")
# — ghcr.io is unreachable, so every container is stuck ImagePullBackOff and the demo never
# comes up. A shared NAT gateway (egress-only, no public inbound on the spokes — the parent
# still dials private vswitch IPs) is the delivery the ECS module's enable_public_ip note calls
# for ("docker pulls need a NAT gateway on the vswitch"), and one NAT covers BOTH spoke types.
resource "alicloud_nat_gateway" "demo" {
  count = var.enable_nat_gateway ? 1 : 0

  vpc_id           = alicloud_vpc.demo.id
  nat_gateway_name = "${var.name}-nat"
  vswitch_id       = alicloud_vswitch.demo[0].id # Enhanced NAT lives in a vswitch
  nat_type         = "Enhanced"
  network_type     = "internet"
}

resource "alicloud_eip_address" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  address_name         = "${var.name}-nat-eip"
  bandwidth            = "10"
  internet_charge_type = "PayByTraffic"
}

resource "alicloud_eip_association" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = alicloud_eip_address.nat[0].id
  instance_id   = alicloud_nat_gateway.demo[0].id
  instance_type = "Nat"
}

# One SNAT rule per vswitch — every spoke on any vswitch egresses through the NAT's EIP.
resource "alicloud_snat_entry" "demo" {
  count = var.enable_nat_gateway ? length(alicloud_vswitch.demo) : 0

  depends_on = [alicloud_eip_association.nat]

  snat_table_id     = alicloud_nat_gateway.demo[0].snat_table_ids
  source_vswitch_id = alicloud_vswitch.demo[count.index].id
  snat_ip           = alicloud_eip_address.nat[0].ip_address
}
