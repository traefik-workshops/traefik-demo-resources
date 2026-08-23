# apps/whoami/alibaba-ecs

Provisions Traefik `whoami` (default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`) on Alibaba Cloud ECS instances — the Alibaba sibling of `apps/whoami/ec2` / `apps/whoami/azure-vm` / `apps/whoami/oci-vm`. Reuses `apps/whoami/cloud-init` (docker-run systemd unit); the `apps` map reads identically to `apps/whoami/ec2`.

Each instance's tags (dotted `traefik.*` keys, exactly like EC2/Azure/OCI tags) are the workload config a Traefik Hub `alibabaECS` provider (`traefik/alibaba-ecs`) discovers. Per-instance IP-mode override: the `traefik.alibabaecs.ipmode` tag.

## Example usage

```hcl
module "whoami_alibaba_ecs" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/alibaba-ecs?ref=v7.0.0"

  vswitch_id         = module.vpc.vswitch_id
  security_group_ids = module.vpc.security_group_ids

  # OTel config for the instrumented fork — added to every container's env
  # (per-app `environment` entries win on collision).
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_SERVICE_NAME           = "whoami-alibaba-ecs"
  }

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-alibaba-ecs" # body shows `Name: whoami-alibaba-ecs`
      tags = {
        "traefik.enable"                                        = "true"
        "traefik.http.routers.whoami.rule"                      = "PathPrefix(`/`)"
        "traefik.http.services.whoami.loadbalancer.server.port" = "80"
      }
    }
  }
}
```

## Prerequisites

- Alibaba Cloud credentials with ECS/VPC permissions; the region comes from the configured `alicloud` provider.
- An existing vswitch + security group to join (e.g. `compute/alibaba/vpc`'s).

## Notes

- whoami needs no cloud API access, so the instances carry no RAM role.
- Docker pulls need outbound internet: either `enable_public_ip = true` or a NAT gateway on the vswitch (e.g. `compute/alibaba/ack`'s `enable_nat_gateway`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cloud_init"></a> [cloud\_init](#module\_cloud\_init) | ../cloud-init | n/a |
| <a name="module_compute"></a> [compute](#module\_compute) | ../../../compute/alibaba/ecs | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs to attach to the instances (Alibaba requires at least one, e.g. compute/alibaba/vpc's security\_group\_ids). Also what the alibabaECS provider's opt-in securityGroupPortDiscovery reads ports from. | `list(string)` | n/a | yes |
| <a name="input_vswitch_id"></a> [vswitch\_id](#input\_vswitch\_id) | ID of the existing vswitch the instances join (e.g. compute/alibaba/vpc's vswitch\_id, so the Traefik child reaches these VMs in-VPC) | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to ECS instances. Each app can have multiple replicas. Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` become dotted-key traefik.* instance tags. | `any` | `{}` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common tags to apply to all instances | `map(string)` | `{}` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Allocate a public IP to each instance (Alibaba grants one when outbound bandwidth > 0). Off by default — the Traefik child dials private IPs (ipMode=private); without it, docker pulls need a NAT gateway on the vswitch. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_image_id"></a> [image\_id](#input\_image\_id) | Boot image ID. Empty = latest public Ubuntu 24.04 x64 image. | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | ECS instance type for all echo servers (default: 2 vCPU / 2 GB economy — the smallest that runs docker reliably) | `string` | `"ecs.e-c1m1.large"` | no |
| <a name="input_system_disk_category"></a> [system\_disk\_category](#input\_system\_disk\_category) | System disk category. ESSD Entry pairs with the economy (e-series) default instance type; switch to cloud\_essd for g/c families. | `string` | `"cloud_essd_entry"` | no |
| <a name="input_system_disk_size"></a> [system\_disk\_size](#input\_system\_disk\_size) | System disk size (GB) per instance | `number` | `40` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each instance. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server instances with their details |
<!-- END_TF_DOCS -->
