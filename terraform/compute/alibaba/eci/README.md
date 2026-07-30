# compute/alibaba/eci

Shared Alibaba Cloud ECI (Elastic Container Instance) container group — the Alibaba sibling of the container-group compute modules. Both `traefik/alibaba-eci` (the multicluster child, one group) and `apps/whoami/alibaba-eci` (the discovered workload, one group per replica) compose this module instead of each declaring `alicloud_eci_container_group` inline.

The module owns the container-group resource and nothing role-specific: the caller renders the container spec (image/commands/args/env/ports/mounts), any volumes, the RAM-role credential and the discovery tags, and passes them in as the opaque `groups` map — the container-platform analog of a VM's rendered user_data. Every group joins the given `vswitch_id`/`security_group_id` and gets a private intranet IP the parent dials in-VPC.

## Example usage

```hcl
module "eci" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/alibaba/eci?ref=v5.1.0"

  vswitch_id        = module.vpc.vswitch_id
  security_group_id = module.vpc.security_group_id

  groups = {
    "whoami-1" = {
      cpu    = 0.25
      memory = 0.5
      containers = [{
        name  = "whoami"
        image = "ghcr.io/zalbiraw/whoami:latest"
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
<!-- END_TF_DOCS -->
