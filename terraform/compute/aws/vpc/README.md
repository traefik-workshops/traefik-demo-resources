# compute/aws/vpc

Provisions an AWS VPC with public and private subnets (via the community `terraform-aws-modules/vpc` module) and a demo security group.

## Example usage

```hcl
module "vpc" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/aws/vpc?ref=v6.1.1"

  name = "demo"
}
```

## Prerequisites

- AWS credentials with VPC/EC2 permissions.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_security_group.demo_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_availability_zones.traefik_demo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | VPC CIDR. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_enable_ipv6"></a> [enable\_ipv6](#input\_enable\_ipv6) | Give the VPC an Amazon-provided /56, carve a /64 out of it for every public subnet, and auto-assign an IPv6 address to each instance launched there (plus an egress-only gateway and a ::/0 route). Off by default so existing IPv4-only callers are untouched. Needed to exercise anything that targets an instance's IPv6 address, e.g. the Hub EC2 provider's `ipMode: ipv6`. | `bool` | `false` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Enable NAT Gateway. | `bool` | `true` | no |
| <a name="input_extra_ingress_ports"></a> [extra\_ingress\_ports](#input\_extra\_ingress\_ports) | Additional TCP ports to open on the demo security group (from 0.0.0.0/0), beyond the default 80/443/8080/22. Used for the Traefik Hub multicluster uplink entrypoint (:9443) on VM/Fargate spokes the parent cluster dials. | `list(number)` | `[]` | no |
| <a name="input_extra_ingress_udp_ports"></a> [extra\_ingress\_udp\_ports](#input\_extra\_ingress\_udp\_ports) | Additional UDP ports to open on the demo security group (from 0.0.0.0/0). Separate from `extra_ingress_ports` because a security-group rule carries exactly one protocol, and because anything that derives a backend port from security-group rules (e.g. the Hub EC2 provider's port discovery) reads that protocol to decide which rules feed a UDP service. | `list(number)` | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | VPC name. | `string` | n/a | yes |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | CIDR blocks for private subnets (one per AZ). Receive a NAT gateway egress when `enable_nat_gateway = true`. Default carves three /24s out of the VPC CIDR. | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24",<br/>  "10.0.3.0/24"<br/>]</pre> | no |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | CIDR blocks for public subnets (one per AZ). Host the internet-facing load balancers and the NAT gateway. Default carves three /24s out of the VPC CIDR. | `list(string)` | <pre>[<br/>  "10.0.4.0/24",<br/>  "10.0.5.0/24",<br/>  "10.0.6.0/24"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | Private route table IDs |
| <a name="output_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#output\_private\_subnet\_cidrs) | Private subnet CIDR blocks, index-aligned with private\_subnet\_ids. Plan-known (straight from the variable), so callers can pin instance addresses with cidrhost() and reference them before anything is applied. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnets IDs |
| <a name="output_public_route_table_ids"></a> [public\_route\_table\_ids](#output\_public\_route\_table\_ids) | Public route table IDs |
| <a name="output_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#output\_public\_subnet\_cidrs) | Public subnet CIDR blocks, index-aligned with public\_subnet\_ids. Plan-known, same purpose as private\_subnet\_cidrs. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnets IDs |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Security group ID |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID |
| <a name="output_vpc_ipv6_cidr_block"></a> [vpc\_ipv6\_cidr\_block](#output\_vpc\_ipv6\_cidr\_block) | The Amazon-provided /56 assigned to the VPC, or "" when `enable_ipv6 = false`. Lets a caller assert dual stack is actually on before asserting anything about IPv6 addressing. |
<!-- END_TF_DOCS -->
