# traefik/aci

Traefik Hub as an Azure Container Instances container group — the Azure sibling of `traefik/ecs` and a **multicluster CHILD**: it joins a Hub parent over a `:9443` uplink and discovers local whoami container groups via its own `hub.providers.aci` provider.

Composes `traefik/shared` (extracted Helm config) exactly like `traefik/ecs`. The child IS a container group running the Hub image (the aci provider ships only in a preview image, `ghcr.io/zalbiraw/traefik-hub` — pass it via `custom_image_*`), with a private vnet-injected IP the parent dials.

Auth is the group's **system-assigned managed identity** (DefaultAzureCredential) + a `Reader` role assignment scoped to the resource group — no client secret. The module appends the provider flags (`--hub.providers.aci.subscriptionID/resourceGroup/ipMode/exposedByDefault/...`) to `custom_arguments`; `subscription_id` defaults from `data.azurerm_client_config`. The file-provider config rides a secret volume (the Hub image is scratch — no shell, so no init-sidecar trick like ECS).

## Example usage

```hcl
module "aci_traefik" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/aci?ref=v7.0.0"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  resource_group_name = azurerm_resource_group.demo.name
  subnet_id           = module.vnet.aci_subnet_id # MUST be delegated to Microsoft.ContainerInstance

  # The aci provider isn't in a Hub release — run the custom image.
  custom_image_registry   = "docker.io"
  custom_image_repository = "zalbiraw/traefik-hub"
  custom_image_tag        = "latest"

  # Hub uplink entrypoint on :9443 (TLS; the parent verifies with insecureSkipVerify).
  multicluster_provider = { enabled = true }
  custom_ports = {
    aciuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }

  # Advertise the provider-discovered service over the uplink (same shape as traefik/ecs).
  file_provider_config = yamlencode({
    http = {
      uplinks = { aci-whoami = { entryPoints = ["aciuplink"] } }
      routers = {
        aci-whoami = {
          rule    = "PathPrefix(`/`)"
          service = "whoami@aci"
          uplinks = ["aci-whoami"]
        }
      }
    }
  })
}
```

## Prerequisites

- Azure credentials with Container Instances/Network permissions **and role-assignment rights** on the resource group (or set `enable_reader_role = false` and assign `Reader` yourself).
- An existing subnet **delegated to `Microsoft.ContainerInstance`** (e.g. `compute/azure/vnet`'s `aci_subnet_id`); the group declares `:9443` among its exposed ports.
- `helm` on the machine running terraform (`traefik/shared` extracts config via `helm template`).

## Notes

- The parent dials `values(module.aci_traefik.private_ips)[0]` (the group's private IP) on `:9443`.
- ACI `commands` replaces the image entrypoint, so the module leads with `/traefik-hub`; the Hub token is inlined in the command (no shell to expand an env var), same trade-off as `traefik/ecs`.
- `enable_dashboard_discovery = false` when the dashboard is advertised via a file-rule uplink (same cleanup as the EC2/ECS spokes).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.0 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_compute"></a> [compute](#module\_compute) | ../../compute/azure/aci | n/a |
| <a name="module_config"></a> [config](#module\_config) | ../shared | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_role_assignment.reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [null_resource.identity_bounce](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the container group is created in (also the aci provider's default discovery scope) | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the existing subnet the container group joins. MUST be delegated to Microsoft.ContainerInstance (compute/azure/vnet's aci\_subnet\_id already is). The parent dials the group's private IP :9443 in-vnet. | `string` | n/a | yes |
| <a name="input_aci_provider"></a> [aci\_provider](#input\_aci\_provider) | Traefik Hub aci provider configuration (hub.providers.aci). subscription\_id defaults to the caller's (data.azurerm\_client\_config); resource\_group defaults to resource\_group\_name. No client credentials: DefaultAzureCredential resolves the group's system-assigned managed identity. Without port\_discovery the provider falls back to the container group's lowest declared exposed port. | <pre>object({<br/>    enabled            = optional(bool, true)<br/>    subscription_id    = optional(string, "")<br/>    resource_group     = optional(string, "")<br/>    ip_mode            = optional(string, "private")<br/>    exposed_by_default = optional(bool, false)<br/>    default_rule       = optional(string, "")<br/>    constraints        = optional(string, "")<br/>    refresh_seconds    = optional(number, null)<br/>    port_discovery     = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_container_cpu"></a> [container\_cpu](#input\_container\_cpu) | vCPU allocation for the Traefik container | `string` | `"1.0"` | no |
| <a name="input_container_memory"></a> [container\_memory](#input\_container\_memory) | Memory allocation (GB) for the Traefik container | `string` | `"2.0"` | no |
| <a name="input_custom_arguments"></a> [custom\_arguments](#input\_custom\_arguments) | Additional CLI arguments for Traefik | `list(string)` | `[]` | no |
| <a name="input_custom_envs"></a> [custom\_envs](#input\_custom\_envs) | Custom environment variables | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_custom_image_registry"></a> [custom\_image\_registry](#input\_custom\_image\_registry) | Custom image registry | `string` | `""` | no |
| <a name="input_custom_image_repository"></a> [custom\_image\_repository](#input\_custom\_image\_repository) | Custom image repository | `string` | `""` | no |
| <a name="input_custom_image_tag"></a> [custom\_image\_tag](#input\_custom\_image\_tag) | Custom image tag | `string` | `""` | no |
| <a name="input_custom_plugins"></a> [custom\_plugins](#input\_custom\_plugins) | Custom plugins to use for the deployment | <pre>map(object({<br/>    moduleName = string<br/>    version    = string<br/>  }))</pre> | `{}` | no |
| <a name="input_custom_ports"></a> [custom\_ports](#input\_custom\_ports) | Custom ports configuration. Typed `any` so it can carry a full Helm `ports.<name>` shape — e.g. a Hub multicluster uplink entrypoint { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } }. | `any` | `{}` | no |
| <a name="input_dashboard_entrypoints"></a> [dashboard\_entrypoints](#input\_dashboard\_entrypoints) | Dashboard entry points | `list(string)` | <pre>[<br/>  "traefik"<br/>]</pre> | no |
| <a name="input_dashboard_insecure"></a> [dashboard\_insecure](#input\_dashboard\_insecure) | Enable insecure dashboard access (no auth) | `bool` | `true` | no |
| <a name="input_dashboard_match_rule"></a> [dashboard\_match\_rule](#input\_dashboard\_match\_rule) | Match rule for the Traefik dashboard router | `string` | `""` | no |
| <a name="input_enable_access_logs"></a> [enable\_access\_logs](#input\_enable\_access\_logs) | Enable Traefik access logs | `bool` | `true` | no |
| <a name="input_enable_ai_gateway"></a> [enable\_ai\_gateway](#input\_enable\_ai\_gateway) | Enable Traefik Hub AI Gateway features | `bool` | `false` | no |
| <a name="input_enable_api_gateway"></a> [enable\_api\_gateway](#input\_enable\_api\_gateway) | Enable Traefik Hub API Gateway features | `bool` | `false` | no |
| <a name="input_enable_dashboard"></a> [enable\_dashboard](#input\_enable\_dashboard) | Enable Traefik dashboard | `bool` | `true` | no |
| <a name="input_enable_dashboard_discovery"></a> [enable\_dashboard\_discovery](#input\_enable\_dashboard\_discovery) | Self-register the Traefik container group via tags (traefik.enable + dashboard router/service) so its OWN aci provider discovers the dashboard as dashboard@aci. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the group isn't self-discovered at all. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_enable_reader_role"></a> [enable\_reader\_role](#input\_enable\_reader\_role) | Assign the Reader role on the provider's resource group to the group's system-assigned identity (requires the caller to hold role-assignment rights, e.g. Owner/User Access Administrator). | `bool` | `true` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra tags to apply to the container group | `map(string)` | `{}` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik/dynamic"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure location | `string` | `"eastus"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Traefik container group | `string` | `"traefik"` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_group_id"></a> [container\_group\_id](#output\_container\_group\_id) | ID of the Traefik container group |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | Private vnet-injected IP of the Traefik container group (the parent dials https://<ip>:9443) |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | Principal ID of the group's system-assigned managed identity (the aci provider's credential) |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of group name to private IP (mirrors traefik/azure-vm's consumption shape: values(...)[0]) |
<!-- END_TF_DOCS -->
