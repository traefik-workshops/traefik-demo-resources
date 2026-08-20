# apps/whoami/ec2

Provisions one or more Traefik `whoami` instances on AWS EC2, wrapping `compute/aws/ec2` and the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`).

## Example usage

```hcl
module "whoami_ec2" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/ec2?ref=v6.3.1"

  # OTel config for the instrumented fork — passed to every container via docker -e
  # (per-app `environment` entries win on collision).
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_SERVICE_NAME           = "whoami-ec2"
  }

  apps = {
    "demo" = {
      replicas = 2
      port     = 80
    }
  }
}
```

## Prerequisites

- AWS credentials with EC2/VPC permissions.

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
| <a name="module_cloud_init"></a> [cloud\_init](#module\_cloud\_init) | ../cloud-init | n/a |
| <a name="module_echo_instances"></a> [echo\_instances](#module\_echo\_instances) | ../../../compute/aws/ec2 | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ami_architecture"></a> [ami\_architecture](#input\_ami\_architecture) | The architecture (x86\_64, arm64) | `string` | `"x86_64"` | no |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to EC2. Each app can have multiple replicas. { name = { replicas, port, name, environment, tags, instance\_name, ... } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` land on the instance (how `traefik.*` discovery tags get set); `instance_name` gives every replica of the app one shared `Name` tag instead of the default per-instance `<app>-<replica>`. | `any` | `{}` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common tags to apply to all instances | `map(string)` | `{}` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create VPC if vpc\_id is not provided | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for all echo servers | `string` | `"t3.micro"` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | List of security group IDs | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs | `list(string)` | `[]` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID | `string` | `""` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each instance. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server instances with their details |
<!-- END_TF_DOCS -->
