# apps/whoami/ecs

Provisions Traefik `whoami` services (default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`) across one or more ECS clusters, wrapping `compute/aws/ecs`.

## Example usage

```hcl
module "whoami_ecs" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/ecs?ref=v6.4.0"

  name = "whoami"

  # OTel config for the instrumented fork — added to every task's container
  # definition (per-app `environment` entries win on collision).
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_SERVICE_NAME           = "whoami-ecs"
  }

  clusters = {
    "demo" = {
      apps               = { "whoami-1" = { port = 80 } }
      subnet_ids         = []
      security_group_ids = []
    }
  }
}
```

## Prerequisites

- AWS credentials with ECS/VPC permissions.

## Notes

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
| <a name="module_echo_services"></a> [echo\_services](#module\_echo\_services) | ../../../compute/aws/ecs | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | Name of the ECS Deployment | `string` | n/a | yes |
| <a name="input_clusters"></a> [clusters](#input\_clusters) | Map of ECS clusters with their echo applications. Each app may set an optional `environment` (map) merged over the module-level `environment` into the task's container definition. | `any` | `{}` | no |
| <a name="input_common_labels"></a> [common\_labels](#input\_common\_labels) | Common labels to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create VPC if vpc\_id is not provided | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables added to every whoami container definition, e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_otlp_gate_address"></a> [otlp\_gate\_address](#input\_otlp\_gate\_address) | OTLP collector base URL (e.g. https://collector.example.com). When set, a sidecar blocks each whoami task from starting until that endpoint accepts an OTLP write. Set it whenever the tasks export telemetry: the whoami fork's exporter has no recovery path, so a task that starts against a collector that is not up yet — or against a stale DNS record still pointing at a destroyed load balancer — serves traffic perfectly and reports nothing. The gate FAILS CLOSED: after 2700s it exits non-zero and the `SUCCESS` dependency stops the task — which ECS then relaunches — instead of releasing a backend that would report nothing. Empty disables the gate. | `string` | `""` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | List of security group IDs for ECS resources | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for ECS resources | `list(string)` | `[]` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for ECS resources | `string` | `""` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image every task runs. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_services"></a> [services](#output\_services) | Map of ECS services |
<!-- END_TF_DOCS -->
