# compute/ibm/vpc

Provisions a demo IBM Cloud VPC (gen2) — the IBM sibling of `compute/alibaba/vpc` / `compute/azure/vnet`: one VPC, zone-spread subnets with **manual address prefixes** (so the CIDRs are deterministic), a **public gateway per zone** (IBM subnets have no outbound internet without one — VMs couldn't pull docker images), and a security group opening the demo ports (80/443/8080/22 to any source, `extra_ingress_ports` intra-VPC only — default `[9443]` for the Hub multicluster uplink).

> **New provider**: this is one of the repo's first IBM Cloud modules and introduces the `IBM-Cloud/ibm` Terraform provider (pinned `~> 1.89`).

IBM security groups attach to instances, not subnets, and deny **both** directions by default — the module adds an allow-all egress rule, and you pass `security_group_id` to the workloads joining the subnets (`apps/whoami/ibm-vpc`, `traefik/ibm-vpc`).

## Example usage

```hcl
module "vpc" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/compute/ibm/vpc?ref=v4.3.0"

  name   = "traefik-demo"
  region = "us-south" # must match the ibm provider's region
}
```

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_ibm"></a> [ibm](#requirement\_ibm) | ~> 1.89 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_ibm"></a> [ibm](#provider\_ibm) | ~> 1.89 |

## Resources

| Name | Type |
|------|------|
| [ibm_is_public_gateway.demo](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_public_gateway) | resource |
| [ibm_is_security_group.demo](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_security_group) | resource |
| [ibm_is_security_group_rule.egress](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_security_group_rule) | resource |
| [ibm_is_security_group_rule.ingress](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_security_group_rule) | resource |
| [ibm_is_subnet.demo](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_subnet) | resource |
| [ibm_is_vpc.demo](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_vpc) | resource |
| [ibm_is_vpc_address_prefix.demo](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_vpc_address_prefix) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | VPC name. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | IBM Cloud region the VPC lands in (zone lookup). Must match the region the ibm provider is configured with. | `string` | n/a | yes |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | VPC CIDR the subnet prefixes are carved out of. Used as the source range for the intra-VPC extra\_ingress\_ports rules. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_extra_ingress_ports"></a> [extra\_ingress\_ports](#input\_extra\_ingress\_ports) | Additional TCP ports to open on the demo security group from INSIDE the VPC only, beyond the default 80/443/8080/22 (those are open to any source). Default covers the Traefik Hub multicluster uplink entrypoint (:9443) on VM spokes the parent cluster dials. | `list(number)` | <pre>[<br/>  9443<br/>]</pre> | no |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource group ID the VPC resources land in. Empty = the account's default resource group. | `string` | `""` | no |
| <a name="input_subnet_cidrs"></a> [subnet\_cidrs](#input\_subnet\_cidrs) | CIDR block per subnet (one subnet each, spread across the region's zones via manual address prefixes). Defaults carve two /24s out of the VPC CIDR. | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Demo security group ID — attach it to the instances joining the subnets (IBM security groups bind to instances, not subnets) |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Demo security group ID as a one-element list (mirrors compute/aws/vpc) |
| <a name="output_subnet_id"></a> [subnet\_id](#output\_subnet\_id) | ID of the first subnet (the convenience pick for single-subnet workloads) |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | IDs of all subnets (zone-spread — compute/ibm/iks can consume the list directly) |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID |
| <a name="output_vpc_name"></a> [vpc\_name](#output\_vpc\_name) | VPC name |
<!-- END_TF_DOCS -->
