data "aws_availability_zones" "traefik_demo" {}

locals {
  # Empty list == the attribute is absent, so IPv4-only callers see no diff.
  ipv6_any = var.enable_ipv6 ? ["::/0"] : []
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name                 = var.name
  cidr                 = var.cidr
  azs                  = data.aws_availability_zones.traefik_demo.names
  private_subnets      = var.private_subnets
  public_subnets       = var.public_subnets
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Public subnets must NOT blanket-assign public IPs (tfsec aws-ec2-no-public-ip-subnet).
  # Each consumer opts in explicitly where it needs one: EC2 instances set
  # associate_public_ip_address (compute/aws/ec2), Fargate tasks set assign_public_ip
  # (compute/aws/ecs — awsvpc ignores this subnet flag anyway), and EKS worker nodes run
  # in the PRIVATE subnets (NAT egress). So subnet auto-assign is redundant — keep it off.
  map_public_ip_on_launch = false

  # Dual stack, opt-in. Unlike the public-IPv4 case above there is no per-instance
  # opt-in to defer to: aws_instance only takes an IPv6 count/list, which would make
  # every caller compute addresses by hand. Auto-assigning on the subnet is what makes
  # `enable_ipv6 = true` sufficient on its own for an instance to come up dual-stack.
  enable_ipv6                                   = var.enable_ipv6
  public_subnet_ipv6_prefixes                   = var.enable_ipv6 ? range(length(var.public_subnets)) : []
  private_subnet_ipv6_prefixes                  = var.enable_ipv6 ? range(length(var.public_subnets), length(var.public_subnets) + length(var.private_subnets)) : []
  public_subnet_assign_ipv6_address_on_creation = var.enable_ipv6
}

resource "aws_security_group" "demo_sg" {
  name        = "${var.name}-sg"
  description = "Security group for ${var.name} demo"
  vpc_id      = module.vpc.vpc_id

  # Allow HTTP
  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = local.ipv6_any
  }

  # Allow HTTPS
  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = local.ipv6_any
  }

  # Allow custom app ports
  ingress {
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = local.ipv6_any
  }

  # Allow SSH
  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = local.ipv6_any
  }

  # Extra ports (e.g. the Hub multicluster uplink :9443 on VM/Fargate spokes)
  dynamic "ingress" {
    for_each = toset(var.extra_ingress_ports)
    content {
      from_port        = ingress.value
      to_port          = ingress.value
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = local.ipv6_any
    }
  }

  # Extra UDP ports (a security-group rule carries one protocol, so these cannot ride
  # along with extra_ingress_ports).
  dynamic "ingress" {
    for_each = toset(var.extra_ingress_udp_ports)
    content {
      from_port        = ingress.value
      to_port          = ingress.value
      protocol         = "udp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = local.ipv6_any
    }
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = local.ipv6_any
  }
}
