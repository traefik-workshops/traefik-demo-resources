# Demo VPC mirroring compute/alibaba/vpc: one VPC gen2, two subnets spread
# across the region's first two zones, and a security group opening the same
# demo ports as the Alibaba/Azure siblings (80/443/8080/22 +
# extra_ingress_ports). IBM specifics: address prefixes are managed manually
# so the subnets carve deterministic CIDRs out of var.cidr, every zone used
# gets a public gateway (VMs have no egress without one — docker pulls need
# it), and the security group carries an explicit allow-all egress rule (IBM
# security groups deny BOTH directions by default). Like Alibaba, IBM security
# groups attach to instances, not subnets — pass security_group_id to the
# workloads that join the subnets.

data "ibm_is_zones" "regional" {
  region = var.region
}

locals {
  resource_group_id = var.resource_group_id != "" ? var.resource_group_id : null

  # Spread across zones (wrapping when there are fewer zones than subnets) so
  # IKS zone-spread worker pools can consume the subnets directly.
  subnet_zones = [
    for i in range(length(var.subnet_cidrs)) :
    data.ibm_is_zones.regional.zones[i % length(data.ibm_is_zones.regional.zones)]
  ]

  zones_used = distinct(local.subnet_zones)
}

resource "ibm_is_vpc" "demo" {
  name           = var.name
  resource_group = local.resource_group_id

  # Manual prefixes: the module pins the subnet CIDRs (mirroring the Alibaba
  # vswitch_cidrs surface) instead of IBM's per-zone auto prefixes, so
  # var.cidr is a truthful source CIDR for the intra-VPC ingress rules.
  address_prefix_management = "manual"
}

resource "ibm_is_vpc_address_prefix" "demo" {
  count = length(var.subnet_cidrs)

  name = "${var.name}-prefix-${count.index + 1}"
  vpc  = ibm_is_vpc.demo.id
  zone = local.subnet_zones[count.index]
  cidr = var.subnet_cidrs[count.index]
}

# One public gateway per zone used — a subnet without one has NO outbound
# internet on IBM VPC (no default SNAT), so VMs couldn't pull docker images.
resource "ibm_is_public_gateway" "demo" {
  for_each = toset(local.zones_used)

  name           = "${var.name}-pgw-${each.value}"
  vpc            = ibm_is_vpc.demo.id
  zone           = each.value
  resource_group = local.resource_group_id
}

resource "ibm_is_subnet" "demo" {
  count = length(var.subnet_cidrs)

  name            = "${var.name}-subnet-${count.index + 1}"
  vpc             = ibm_is_vpc.demo.id
  zone            = local.subnet_zones[count.index]
  ipv4_cidr_block = var.subnet_cidrs[count.index]
  public_gateway  = ibm_is_public_gateway.demo[local.subnet_zones[count.index]].id
  resource_group  = local.resource_group_id

  depends_on = [ibm_is_vpc_address_prefix.demo]
}

locals {
  # Public-facing demo ports (any source) + extra ports opened intra-VPC only
  # (e.g. the Hub multicluster uplink :9443 on VM spokes the parent cluster
  # dials).
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

resource "ibm_is_security_group" "demo" {
  name           = "${var.name}-sg"
  vpc            = ibm_is_vpc.demo.id
  resource_group = local.resource_group_id
}

resource "ibm_is_security_group_rule" "ingress" {
  for_each = local.ingress_rules

  group     = ibm_is_security_group.demo.id
  direction = "inbound"
  remote    = each.value.cidr

  tcp {
    port_min = each.value.port
    port_max = each.value.port
  }
}

# IBM security groups have no implicit egress — without this rule the
# instances can't even reach the public gateway for image pulls.
resource "ibm_is_security_group_rule" "egress" {
  group     = ibm_is_security_group.demo.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}
