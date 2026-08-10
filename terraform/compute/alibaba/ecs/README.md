# compute/alibaba/ecs

The shared Alibaba Cloud ECS instance fleet — the Alibaba sibling of `compute/aws/ec2` and `compute/nutanix/vm`. Both the Traefik gateway (`traefik/alibaba-ecs`) and the whoami backend (`apps/whoami/alibaba-ecs`) compose this module so the `alicloud_instance` (plus the optional security-group escape hatch and the static private-IP pin) is defined once.

Takes fully-rendered `user_data` as an **opaque string** — it holds no Hub or whoami logic and does not generate cloud-init. Callers render their own cloud-init and pass the result in. Naming, sizing, image resolution (latest Ubuntu 24.04 when `image_id` is empty), the `enable_public_ip` bandwidth trick, the `private_ips` pin, and the optional `enable_security_group` group all live here.

## Example usage

```hcl
module "compute" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/alibaba/ecs?ref=v6.1.2"

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
<!-- END_TF_DOCS -->
