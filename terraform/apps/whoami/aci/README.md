# apps/whoami/aci

Provisions Traefik `whoami` (default image: the OTel-instrumented fork `ghcr.io/zalbiraw/whoami`) as Azure Container Instances container groups — the Azure sibling of `apps/whoami/ecs`. Each app replica is one container group with a private, vnet-injected IP; the `apps` map reads identically to `apps/whoami/ec2`.

Each group's Azure tags (dotted `traefik.*` keys, exactly like ECS docker labels) are the workload config a Traefik Hub `aci` provider (`traefik/aci`) discovers. Without `portDiscovery`, the provider falls back to the group's lowest declared exposed port (declared from `apps.<name>.port`, default 80).

## Example usage

```hcl
module "whoami_aci" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/aci?ref=v5.2.2"

  resource_group_name = azurerm_resource_group.demo.name
  subnet_id           = module.vnet.aci_subnet_id # MUST be delegated to Microsoft.ContainerInstance

  # OTel config for the instrumented fork — added to every container's env
  # (per-app `environment` entries win on collision).
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_SERVICE_NAME           = "whoami-aci"
  }

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-aci" # body shows `Name: whoami-aci`
      tags = {
        "traefik.enable"                                          = "true"
        "traefik.http.services.whoami.loadbalancer.server.port" = "80"
      }
    }
  }
}
```

## Prerequisites

- Azure credentials with Container Instances/Network permissions and an existing resource group.
- An existing subnet **delegated to `Microsoft.ContainerInstance`** (e.g. `compute/azure/vnet`'s `aci_subnet_id`) — or set `create_vnet = true`.

## Notes

- Container groups are `Private` (vnet-injected) — the Traefik child dials them in-vnet (`ipMode=private`).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_container_group.whoami](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the container groups are created in | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to ACI. Each app can have multiple replicas (one container group each). Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container. | `any` | `{}` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common tags to apply to all container groups | `map(string)` | `{}` | no |
| <a name="input_container_cpu"></a> [container\_cpu](#input\_container\_cpu) | vCPU allocation per whoami container | `string` | `"0.5"` | no |
| <a name="input_container_memory"></a> [container\_memory](#input\_container\_memory) | Memory allocation (GB) per whoami container | `string` | `"1.0"` | no |
| <a name="input_create_vnet"></a> [create\_vnet](#input\_create\_vnet) | Create a demo VNet (compute/azure/vnet) if subnet\_id is not provided. Off by default — these container groups normally join an existing delegated subnet. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables added to every whoami container, e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure location | `string` | `"eastus"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the existing subnet the container groups join. MUST be delegated to Microsoft.ContainerInstance (compute/azure/vnet's aci\_subnet\_id already is). | `string` | `""` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image every container group runs. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/zalbiraw/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_groups"></a> [container\_groups](#output\_container\_groups) | Map of all echo server container groups with their details |
<!-- END_TF_DOCS -->
