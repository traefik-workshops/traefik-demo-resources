# compute/alibaba/ecs

The shared Alibaba Cloud ECS instance fleet — the Alibaba sibling of `compute/aws/ec2` and `compute/nutanix/vm`. Both the Traefik gateway (`traefik/alibaba-ecs`) and the whoami backend (`apps/whoami/alibaba-ecs`) compose this module so the `alicloud_instance` (plus the optional security-group escape hatch and the static private-IP pin) is defined once.

Takes fully-rendered `user_data` as an **opaque string** — it holds no Hub or whoami logic and does not generate cloud-init. Callers render their own cloud-init and pass the result in. Naming, sizing, image resolution (latest Ubuntu 24.04 when `image_id` is empty), the `enable_public_ip` bandwidth trick, the `private_ips` pin, and the optional `enable_security_group` group all live here.

## Example usage

```hcl
module "compute" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/alibaba/ecs?ref=v6.5.0"

  name       = "whoami"
  replicas   = 2
  vswitch_id = module.vpc.vswitch_id

  security_group_ids = [module.vpc.security_group_id]
  user_data          = module.cloud_init.rendered
  tags               = { "traefik.enable" = "true" }
}
```

## Prerequisites

- Alibaba Cloud credentials with ECS permissions.
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_alicloud"></a> [alicloud](#requirement\_alicloud) | ~> 1.220 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_alicloud"></a> [alicloud](#provider\_alicloud) | ~> 1.220 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [alicloud_instance.ecs](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/instance) | resource |
| [alicloud_security_group.this](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/security_group) | resource |
| [alicloud_security_group_rule.ingress](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/security_group_rule) | resource |
| [alicloud_images.ubuntu](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/data-sources/images) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | Base name for the instances. Each replica is named "<name>-<index>". | `string` | n/a | yes |
| <a name="input_vswitch_id"></a> [vswitch\_id](#input\_vswitch\_id) | ID of the existing vswitch the instances join (e.g. compute/alibaba/vpc's vswitch\_id). | `string` | n/a | yes |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Allocate a public IP to each instance (Alibaba grants one when outbound bandwidth > 0). Off by default — callers dial private IPs; without it, docker pulls need a NAT gateway on the vswitch. | `bool` | `false` | no |
| <a name="input_enable_security_group"></a> [enable\_security\_group](#input\_enable\_security\_group) | Create a security group opening security\_group\_ingress\_ports to the instances from security\_group\_source\_cidr (mirrors traefik/oci-vm's enable\_nsg). Off by default — compute/alibaba/vpc's group already opens the demo ports. Requires vpc\_id. | `bool` | `false` | no |
| <a name="input_image_id"></a> [image\_id](#input\_image\_id) | Boot image ID. Empty = latest public Ubuntu 24.04 x64 image. | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | ECS instance type. | `string` | `"ecs.e-c1m2.large"` | no |
| <a name="input_private_ips"></a> [private\_ips](#input\_private\_ips) | Fixed private IPs, one per instance index (instance idx N gets private\_ips[N]; extra instances fall back to DHCP). Each address must sit in vswitch\_id's CIDR outside Alibaba's reserved first-3/last-1 hosts. Pinning makes the address plan-known AND stable across instance recreation. | `list(string)` | `[]` | no |
| <a name="input_replica_start_index"></a> [replica\_start\_index](#input\_replica\_start\_index) | Starting index for replica numbering (Default: 1). | `number` | `1` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Number of instances to create (the gateway calls with 1, whoami with N). | `number` | `1` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Existing security group IDs to attach to the instances (Alibaba requires at least one unless enable\_security\_group is on, e.g. compute/alibaba/vpc's security\_group\_ids). | `list(string)` | `[]` | no |
| <a name="input_security_group_ingress_ports"></a> [security\_group\_ingress\_ports](#input\_security\_group\_ingress\_ports) | TCP ports the module-created security group opens on the instances. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials. | `list(number)` | <pre>[<br/>  80,<br/>  443,<br/>  8080,<br/>  9443<br/>]</pre> | no |
| <a name="input_security_group_source_cidr"></a> [security\_group\_source\_cidr](#input\_security\_group\_source\_cidr) | Source CIDR the module-created security group allows. Default covers RFC1918 VPCs (compute/alibaba/vpc's VPC is 10.0.0.0/16). | `string` | `"10.0.0.0/8"` | no |
| <a name="input_system_disk_category"></a> [system\_disk\_category](#input\_system\_disk\_category) | System disk category. ESSD Entry pairs with the economy (e-series) instance types; switch to cloud\_essd for g/c families. | `string` | `"cloud_essd_entry"` | no |
| <a name="input_system_disk_size"></a> [system\_disk\_size](#input\_system\_disk\_size) | System disk size (GB) per instance. | `number` | `40` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to every instance in this call (dotted-key traefik.* tags are the alibabaECS provider's workload/dashboard config). | `map(string)` | `{}` | no |
| <a name="input_user_data"></a> [user\_data](#input\_user\_data) | Fully-rendered cloud-init/user-data as an opaque string. The module base64-encodes it before handing it to the instance. | `string` | `""` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC the module-created security group is created in. Only required when enable\_security\_group = true. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of instances keyed by instance name -> { id, name, private\_ip, public\_ip } |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their private IP addresses |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their public IP addresses (empty string when enable\_public\_ip = false) |
<!-- END_TF_DOCS -->
