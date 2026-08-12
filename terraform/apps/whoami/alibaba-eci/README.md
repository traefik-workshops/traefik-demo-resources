# apps/whoami/alibaba-eci

Provisions Traefik `whoami` (default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`) as Alibaba Cloud ECI container groups — the Alibaba sibling of `apps/whoami/aci` and `apps/whoami/oci-ci`. Each app replica is one container group with a private vswitch IP; the `apps` map reads identically to `apps/whoami/ec2`.

Each group's tags (dotted `traefik.*` keys, exactly like ACI/OCI tags) are the workload config a Traefik Hub `alibabaECI` provider (`traefik/alibaba-eci`) discovers. With `portDiscovery`, the provider falls back to the group's lowest declared container port — this module declares `apps.<name>.port` (default 80) on the container, so a group serving on port 80 needs no port tag.

## Example usage

```hcl
module "whoami_alibaba_eci" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/alibaba-eci?ref=v6.2.8"

  vswitch_id        = module.vpc.vswitch_id
  security_group_id = module.vpc.security_group_id

  # OTel config for the instrumented fork — added to every container's env
  # (per-app `environment` entries win on collision).
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_SERVICE_NAME           = "whoami-alibaba-eci"
  }

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-alibaba-eci" # body shows `Name: whoami-alibaba-eci`
      tags = {
        "traefik.enable" = "true"
        # No port tag needed: the declared port 80 is the portDiscovery fallback.
      }
    }
  }
}
```

## Prerequisites

- Alibaba Cloud credentials with ECI/VPC permissions; the region comes from the configured `alicloud` provider.
- An existing vswitch + security group (e.g. `compute/alibaba/vpc`'s). The vswitch's zone must support ECI.

## Notes

- Container groups get private vswitch IPs only — the Traefik child dials them in-VPC (`ipMode=private`).
- Per-group IP-mode override: the `traefik.alibabaeci.ipmode` tag.
- Image pulls need outbound internet — a NAT gateway on the VPC (e.g. `compute/alibaba/ack`'s `enable_nat_gateway`).

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
| <a name="module_compute"></a> [compute](#module\_compute) | ../../../compute/alibaba/eci | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | Security group ID attached to the container groups (required by ECI, e.g. compute/alibaba/vpc's security\_group\_id) | `string` | n/a | yes |
| <a name="input_vswitch_id"></a> [vswitch\_id](#input\_vswitch\_id) | ID of the existing vswitch the container groups join (e.g. compute/alibaba/vpc's vswitch\_id, so the Traefik child reaches them in-VPC) | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to ECI. Each app can have multiple replicas (one container group each). Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` become dotted-key traefik.* container-group tags. | `any` | `{}` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common tags to apply to all container groups | `map(string)` | `{}` | no |
| <a name="input_container_cpu"></a> [container\_cpu](#input\_container\_cpu) | vCPUs per container group (0.25 is ECI's minimum) | `number` | `0.25` | no |
| <a name="input_container_memory"></a> [container\_memory](#input\_container\_memory) | Memory (GB) per container group (0.5 is ECI's minimum for 0.25 vCPU) | `number` | `0.5` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables added to every whoami container, e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image every container group runs. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_groups"></a> [container\_groups](#output\_container\_groups) | Map of all echo server container groups with their details |
<!-- END_TF_DOCS -->
