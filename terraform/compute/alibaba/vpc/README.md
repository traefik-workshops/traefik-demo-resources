# compute/alibaba/vpc

Base networking for Alibaba Cloud demos — the Alibaba sibling of `compute/azure/vnet` and `compute/aws/vpc`. One VPC, two zone-spread vswitches (ECS VMs, ECI container groups and ACK nodes can all share them — no delegation concept), and a security group opening the demo ports: 80/443/8080/22 from anywhere, plus `extra_ingress_ports` (default `[9443]`, the Hub multicluster uplink) from inside the VPC only.

Alibaba security groups attach to **workloads** (ECS instances, ECI container groups), not subnets — pass `security_group_id` to whatever joins the vswitches.

## Example usage

```hcl
module "vpc" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/alibaba/vpc?ref=v5.4.2"

  name = "traefik-demo"
}

# ECS/ECI workloads then join:
#   vswitch_id        = module.vpc.vswitch_id
#   security_group_id = module.vpc.security_group_id
```

## Notes

- The region comes from the configured `alicloud` provider.
- The `:9443` uplink port is only reachable from inside the VPC (`cidr`) — the multicluster parent must share the VPC (or peer into it).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_alicloud"></a> [alicloud](#requirement\_alicloud) | ~> 1.220 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_alicloud"></a> [alicloud](#provider\_alicloud) | ~> 1.220 |

## Resources

| Name | Type |
|------|------|
| [alicloud_security_group.demo](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/security_group) | resource |
| [alicloud_security_group_rule.ingress](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/security_group_rule) | resource |
| [alicloud_vpc.demo](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/vpc) | resource |
| [alicloud_vswitch.demo](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/vswitch) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | VPC name. | `string` | n/a | yes |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | VPC CIDR. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_extra_ingress_ports"></a> [extra\_ingress\_ports](#input\_extra\_ingress\_ports) | Additional TCP ports to open on the demo security group from INSIDE the VPC only, beyond the default 80/443/8080/22 (those are open to any source). Default covers the Traefik Hub multicluster uplink entrypoint (:9443) on ECS/ECI spokes the parent cluster dials. | `list(number)` | <pre>[<br/>  9443<br/>]</pre> | no |
| <a name="input_vswitch_cidrs"></a> [vswitch\_cidrs](#input\_vswitch\_cidrs) | CIDR block per vswitch (one vswitch each, spread across the region's zones). Defaults carve two /24s out of the VPC CIDR. | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Demo security group ID — attach it to the ECS instances / ECI container groups joining the vswitches (Alibaba security groups bind to workloads, not subnets) |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Demo security group ID as a one-element list (mirrors compute/aws/vpc) |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID |
| <a name="output_vpc_name"></a> [vpc\_name](#output\_vpc\_name) | VPC name |
| <a name="output_vswitch_id"></a> [vswitch\_id](#output\_vswitch\_id) | ID of the first vswitch (the convenience pick for single-vswitch workloads) |
| <a name="output_vswitch_ids"></a> [vswitch\_ids](#output\_vswitch\_ids) | IDs of all vswitches (zone-spread — ACK control planes / node pools can consume the list directly) |
<!-- END_TF_DOCS -->
