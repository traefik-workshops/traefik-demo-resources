# compute/aws/ec2

Provisions a fleet of EC2 instances from an `apps` map (each app supports replicas, Docker-based user-data, optional VPC creation).

## Example usage

```hcl
module "ec2" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/aws/ec2?ref=v6.0.0"

  apps = {
    "whoami" = {
      replicas     = 2
      port         = 80
      docker_image = "traefik/whoami:latest"
    }
  }
}
```

## Prerequisites

- AWS credentials with EC2/VPC permissions.
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ../vpc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_instance.ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [terraform_data.replacement_trigger](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_ami.amazon_linux_2023](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ami_architecture"></a> [ami\_architecture](#input\_ami\_architecture) | AMI architecture (x86\_64 or arm64) | `string` | `"x86_64"` | no |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy with multiple replicas | <pre>map(object({<br/>    replicas            = optional(number, 1)<br/>    subnet_ids          = optional(list(string), [])<br/>    port                = optional(number, 80)<br/>    docker_image        = optional(string, "traefik/whoami:latest")<br/>    docker_options      = optional(string, "") # Docker run flags: -e, -p, -v, etc.<br/>    container_arguments = optional(string, "") # Container CMD/ARGS: --flag=value, etc.<br/>    tags                = optional(map(string), {})<br/>    # Shared `Name` tag for every replica of this app. Empty (the default) keeps the<br/>    # per-instance "<app>-<replica>" name, which is what makes each instance uniquely<br/>    # identifiable. Set it when a discovery provider keys its service name off the Name<br/>    # tag and you want several instances to land behind ONE service — Traefik Hub's EC2<br/>    # provider merges same-Name instances into a single load balancer, and that merge<br/>    # cannot be exercised while every instance is named differently.<br/>    instance_name = optional(string, "")<br/>  }))</pre> | n/a | yes |
| <a name="input_associate_public_ip_address"></a> [associate\_public\_ip\_address](#input\_associate\_public\_ip\_address) | Associate a public IP address with an instance in a VPC | `bool` | `true` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common tags to apply to all instances | `map(string)` | `{}` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create VPC if vpc\_id is not provided | `bool` | `true` | no |
| <a name="input_enable_acme_setup"></a> [enable\_acme\_setup](#input\_enable\_acme\_setup) | Enable ACME storage setup for Let's Encrypt certificates | `bool` | `false` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Create a NAT gateway in the VPC (only when create\_vpc = true). Defaults false — these instances run in PUBLIC subnets with public IPs (IGW egress), so the NAT (which only serves the unused private subnets) is pure cost. | `bool` | `false` | no |
| <a name="input_extra_ingress_ports"></a> [extra\_ingress\_ports](#input\_extra\_ingress\_ports) | Additional TCP ports to open on the created VPC's security group (only when create\_vpc = true). Passed through to compute/aws/vpc — e.g. [9443] for a Hub multicluster uplink entrypoint. | `list(number)` | `[]` | no |
| <a name="input_iam_instance_profile"></a> [iam\_instance\_profile](#input\_iam\_instance\_profile) | IAM instance profile name to attach to EC2 instances | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type | `string` | `"t3.large"` | no |
| <a name="input_private_ips"></a> [private\_ips](#input\_private\_ips) | Fixed private IPs, one per instance index (instance idx N gets private\_ips[N]; extra instances fall back to DHCP). Each address must sit in the subnet that instance lands in (subnet\_ids[idx % length]) and avoid AWS's reserved first-4/last-1 hosts. Pinning makes the address plan-known AND stable across instance recreation — a hub dialing this child never goes stale. | `list(string)` | `[]` | no |
| <a name="input_replica_start_index"></a> [replica\_start\_index](#input\_replica\_start\_index) | Starting index for replica numbering (Default: 1) | `number` | `1` | no |
| <a name="input_root_block_device_size"></a> [root\_block\_device\_size](#input\_root\_block\_device\_size) | Root block device size in GB. Must be >= the AMI's root snapshot — the Amazon Linux 2023 AMI snapshot is 30GB, so 20 now fails RunInstances with InvalidBlockDeviceMapping. | `number` | `30` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | List of security group IDs to associate with the instances (used if not creating VPC) | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs | `list(string)` | `[]` | no |
| <a name="input_user_data_override"></a> [user\_data\_override](#input\_user\_data\_override) | Optional user data script to override the default Docker-based generation | `string` | `""` | no |
| <a name="input_user_data_overrides"></a> [user\_data\_overrides](#input\_user\_data\_overrides) | Optional map of user data scripts to override the default Docker-based generation per instance key | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all instances with their details |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance keys to private IP addresses |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance keys to public IP addresses |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID the instances are attached to (created VPC, or the provided vpc\_id). |
<!-- END_TF_DOCS -->
