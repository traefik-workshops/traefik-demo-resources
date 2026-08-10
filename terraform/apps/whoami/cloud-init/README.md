# apps/whoami/cloud-init

> **Status:** stub module. Intentionally minimal; expand only if a demo needs it. Documented at this minimum scope rather than removed because demo wrappers reference it.

Renders a cloud-init template that installs Docker and `docker run`s the `whoami` image (default: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`) as a systemd unit, publishing a configurable host port. No resources — output-only.

## Example usage

```hcl
module "whoami_cloud_init" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/cloud-init?ref=v6.1.2"

  arch = "amd64"
  port = 80

  # OTel config for the instrumented fork — passed to the container via docker -e.
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_SERVICE_NAME           = "whoami"
  }
}
```

## Prerequisites

- Consumer module that accepts cloud-init user data (e.g., `compute/aws/ec2`, `compute/nutanix/vm`).

## Notes

- Stub module. Kept intentionally minimal because demo wrappers reference it; expand only if a demo needs more.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |

## Providers

No providers.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_arch"></a> [arch](#input\_arch) | The architecture (amd64, arm64) | `string` | `"amd64"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Extra environment variables for the container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. | `map(string)` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Identifier surfaced as `Name:` in the whoami response | `string` | `""` | no |
| <a name="input_port"></a> [port](#input\_port) | Host port whoami is published on (docker -p <port>:80) | `number` | `80` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run. Untagged references get `:` + whoami\_version appended (e.g. `traefik/whoami` + `v1.11.0`). | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_rendered"></a> [rendered](#output\_rendered) | Rendered. |
<!-- END_TF_DOCS -->
