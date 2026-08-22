# compute/alibaba/eci

Shared Alibaba Cloud ECI (Elastic Container Instance) container group — the Alibaba sibling of the container-group compute modules. Both `traefik/alibaba-eci` (the multicluster child, one group) and `apps/whoami/alibaba-eci` (the discovered workload, one group per replica) compose this module instead of each declaring `alicloud_eci_container_group` inline.

The module owns the container-group resource and nothing role-specific: the caller renders the container spec (image/commands/args/env/ports/mounts), any volumes, the RAM-role credential and the discovery tags, and passes them in as the opaque `groups` map — the container-platform analog of a VM's rendered user_data. Every group joins the given `vswitch_id`/`security_group_id` and gets a private intranet IP the parent dials in-VPC.

## Example usage

```hcl
module "eci" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/alibaba/eci?ref=v6.7.0"

  vswitch_id        = module.vpc.vswitch_id
  security_group_id = module.vpc.security_group_id

  groups = {
    "whoami-1" = {
      cpu    = 0.25
      memory = 0.5
      containers = [{
        name  = "whoami"
        image = "ghcr.io/traefik-workshops/whoami:latest"
        ports = [{ port = 80 }]
      }]
      tags = { "traefik.enable" = "true" }
    }
  }
}
```

## Notes

- Group key = `container_group_name` = output key. `private_ips` is `{ name => intranet_ip }`; the parent dials `https://<intranet_ip>:9443`.
- RAM-role creation, provider CLI args and discovery tags stay in the callers — this module only consumes the rendered `ram_role_name`, container spec and `tags`.

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
| [alicloud_eci_container_group.this](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/eci_container_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_groups"></a> [groups](#input\_groups) | Map of container groups to create, keyed by container\_group\_name (the key is<br/>used verbatim as the group name and as the output key). The gateway passes a<br/>single entry; whoami passes one per replica. Each group carries its already<br/>rendered, role-specific container spec, volumes, RAM role and tags — this<br/>module treats them as opaque and only owns the container-group resource. | <pre>map(object({<br/>    cpu    = number<br/>    memory = number<br/>    # The metadata-served RAM role the container assumes (null = unset). Only the<br/>    # Traefik child sets it (its alibabaECI provider's keyless credential).<br/>    ram_role_name = optional(string)<br/>    # Container specs (both callers declare exactly one). Fields left null/empty<br/>    # are not emitted, so a caller that never sets commands/args/env/mounts<br/>    # renders a container identical to a hand-written static block.<br/>    containers = list(object({<br/>      name     = string<br/>      image    = string<br/>      commands = optional(list(string))<br/>      args     = optional(list(string))<br/>      ports = optional(list(object({<br/>        port     = number<br/>        protocol = optional(string, "TCP")<br/>      })), [])<br/>      environment_vars = optional(map(string), {})<br/>      volume_mounts = optional(list(object({<br/>        name       = string<br/>        mount_path = string<br/>      })), [])<br/>    }))<br/>    # Container-group volumes (e.g. a ConfigFileVolume delivering file-provider<br/>    # config). Empty for workloads that mount nothing.<br/>    volumes = optional(list(object({<br/>      name = string<br/>      type = string<br/>      config_file_volume_config_file_to_paths = optional(list(object({<br/>        path    = string<br/>        content = string<br/>      })), [])<br/>    })), [])<br/>    # Dotted-key traefik.* tags — the alibabaECI provider's workload config.<br/>    tags = optional(map(string), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | Security group ID attached to every container group (required by ECI, e.g. compute/alibaba/vpc's security\_group\_id). | `string` | n/a | yes |
| <a name="input_vswitch_id"></a> [vswitch\_id](#input\_vswitch\_id) | ID of the existing vswitch every container group joins (the parent dials a group's private intranet IP in-VPC, e.g. compute/alibaba/vpc's vswitch\_id). | `string` | n/a | yes |
| <a name="input_restart_policy"></a> [restart\_policy](#input\_restart\_policy) | Container-group restart policy (Always \| OnFailure \| Never). | `string` | `"Always"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all container groups keyed by name, with their details. |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of container-group names to their private intranet IP (the address the parent dials in-VPC). |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of container-group names to their public internet IP (empty unless the group was assigned one). |
<!-- END_TF_DOCS -->
