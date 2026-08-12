# traefik/alibaba-eci

Traefik Hub as one Alibaba Cloud ECI container group — the Alibaba sibling of `traefik/aci` and `traefik/oci-ci`, and a **multicluster CHILD**: it joins a Hub parent over a `:9443` uplink and discovers local whoami container groups via its own `hub.providers.alibabaECI` provider.

Composes `traefik/shared` (extracted Helm config) exactly like `traefik/aci`: the Hub image (`ghcr.io/zalbiraw/traefik-hub` via `custom_image_*`; the alibabaECI provider ships only there) runs with `commands = ["/traefik-hub"]` and the token + extracted args as `args` (exec'd with no shell, so the token is inlined). The Hub image is scratch — a **ConfigFileVolume** (ECI's config-file volume mechanism) carries the file-provider config.

**Auth — keyless by default:** ECI container groups take an instance RAM role (`ram_role_name`, trusted by `ecs.aliyuncs.com` — ECI serves the same `100.100.100.200` metadata endpoint as ECS). `enable_ram_role` (default on) creates the role + a read-only `eci:Describe*` policy and binds it, and the provider's empty-credential default chain (env → profile → RAM role via metadata) consumes it. Fallback for accounts without RAM rights: the `access_key_id`/`access_key_secret` (+ optional STS `security_token`) variables, delivered as `--hub.providers.alibabaECI.accessKey*` flags.

**Workload config note:** the alibabaECI provider reads Traefik labels from **tags** with dotted keys, exactly like `traefik/aci`'s Azure tags. Port precedence: port tag > declared-container-port discovery (opt-in `port_discovery`, lowest declared port). ECI has no "published port" list — `:9443` reachability is governed by the attached security group (`compute/alibaba/vpc` opens it intra-VPC via `extra_ingress_ports`). Per-group IP-mode override: the `traefik.alibabaeci.ipmode` tag.

## Example usage

```hcl
module "alibaba_eci_traefik" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/alibaba-eci?ref=v6.3.0"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  vswitch_id        = module.vpc.vswitch_id
  security_group_id = module.vpc.security_group_id

  # The alibabaECI provider isn't in a Hub release — run the custom image.
  enable_preview_mode     = true
  custom_image_registry   = "docker.io"
  custom_image_repository = "zalbiraw/traefik-hub"
  custom_image_tag        = "latest"

  # Hub uplink entrypoint on :9443 (TLS; the parent verifies with insecureSkipVerify).
  multicluster_provider = { enabled = true }
  custom_ports = {
    alibabaeciuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }

  # Advertise the provider-discovered service over the uplink (same shape as traefik/aci).
  file_provider_config = yamlencode({
    http = {
      uplinks = { alibabaeci-whoami = { entryPoints = ["alibabaeciuplink"] } }
      routers = {
        alibabaeci-whoami = {
          rule    = "PathPrefix(`/`)"
          service = "whoami@alibabaeci"
          uplinks = ["alibabaeci-whoami"]
        }
      }
    }
  })
}
```

## Prerequisites

- Alibaba Cloud credentials with ECI/VPC permissions **and RAM rights** (role + policy) — or set `enable_ram_role = false` and pass `access_key_id`/`access_key_secret`.
- A joinable vswitch + security group; `:9443` must be reachable in-VPC (e.g. `compute/alibaba/vpc` with `extra_ingress_ports = [9443]`).
- `helm` on the machine running terraform (`traefik/shared` extracts config via `helm template`).

## Notes

- One container group — the parent dials `values(module.alibaba_eci_traefik.private_ips)[0]` on `:9443` (also exposed flat as `ip_address`).
- `enable_dashboard_discovery = false` when the dashboard is advertised via a file-rule uplink (same cleanup as the ACI/OCI spokes).
- RAM names derive from `name` and are account-global — two instantiations need distinct `name`s (or `enable_ram_role = false` on one).

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

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_compute"></a> [compute](#module\_compute) | ../../compute/alibaba/eci | n/a |
| <a name="module_config"></a> [config](#module\_config) | ../shared | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [alicloud_ram_policy.traefik](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/ram_policy) | resource |
| [alicloud_ram_role.traefik](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/ram_role) | resource |
| [alicloud_ram_role_policy_attachment.traefik](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/ram_role_policy_attachment) | resource |
| [alicloud_regions.current](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/data-sources/regions) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | Security group ID attached to the container group (required by ECI, e.g. compute/alibaba/vpc's security\_group\_id — its extra\_ingress\_ports must cover the :9443 uplink) | `string` | n/a | yes |
| <a name="input_vswitch_id"></a> [vswitch\_id](#input\_vswitch\_id) | ID of the existing vswitch the container group joins (the parent dials the group's private IP :9443 in-VPC, e.g. compute/alibaba/vpc's vswitch\_id) | `string` | n/a | yes |
| <a name="input_access_key_id"></a> [access\_key\_id](#input\_access\_key\_id) | Alibaba Cloud access key ID the alibabaECI provider authenticates with — the fallback when enable\_ram\_role is off (e.g. no RAM rights). Empty = the default credential chain (the RAM role). | `string` | `""` | no |
| <a name="input_access_key_secret"></a> [access\_key\_secret](#input\_access\_key\_secret) | Alibaba Cloud access key secret paired with access\_key\_id | `string` | `""` | no |
| <a name="input_alibabaeci_provider"></a> [alibabaeci\_provider](#input\_alibabaeci\_provider) | Traefik Hub alibabaECI provider configuration (hub.providers.alibabaECI). region\_id defaults to the group's own region (from the alicloud provider); endpoint defaults to the regional one. No access keys here: empty credentials make the provider fall through the default chain (env -> profile -> RAM role via metadata — see enable\_ram\_role); the access\_key\_* variables are the explicit fallback. Without port\_discovery the provider needs explicit port tags; with it, it falls back to the group's lowest declared container port. | <pre>object({<br/>    enabled            = optional(bool, true)<br/>    region_id          = optional(string, "")<br/>    endpoint           = optional(string, "")<br/>    ip_mode            = optional(string, "private")<br/>    exposed_by_default = optional(bool, false)<br/>    default_rule       = optional(string, "")<br/>    constraints        = optional(string, "")<br/>    refresh_seconds    = optional(number, null)<br/>    port_discovery     = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_container_cpu"></a> [container\_cpu](#input\_container\_cpu) | vCPUs for the Traefik container group | `number` | `1` | no |
| <a name="input_container_memory"></a> [container\_memory](#input\_container\_memory) | Memory (GB) for the Traefik container group | `number` | `4` | no |
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
| <a name="input_enable_dashboard_discovery"></a> [enable\_dashboard\_discovery](#input\_enable\_dashboard\_discovery) | Self-register the Traefik container group via tags (traefik.enable + dashboard router/service) so its OWN alibabaECI provider discovers the dashboard as dashboard@alibabaeci. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the group isn't self-discovered at all. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (required for provider builds not yet in a Hub release, e.g. alibabaECI) | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_enable_ram_role"></a> [enable\_ram\_role](#input\_enable\_ram\_role) | Create a RAM role (trusted by ecs.aliyuncs.com — the trust ECI's metadata mechanism requires) + read-only eci:Describe* policy and bind it to the group — the alibabaECI provider's keyless credential via the default chain (env -> profile -> RAM role metadata). RAM names are account-global (derived from name); disable when the demo already created them, and pass access keys instead. | `bool` | `true` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra tags to apply to the container group | `map(string)` | `{}` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik/dynamic"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Traefik container group (also the base name for its RAM resources) | `string` | `"traefik"` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_security_token"></a> [security\_token](#input\_security\_token) | Alibaba Cloud STS security token — only for temporary (STS) access keys | `string` | `""` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_group_id"></a> [container\_group\_id](#output\_container\_group\_id) | ID of the Traefik ECI container group |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | Private vswitch IP of the Traefik container group (the parent dials https://<ip>:9443) |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance name to private IP (mirrors traefik/alibaba-ecs's consumption shape: values(...)[0]) |
| <a name="output_ram_role_name"></a> [ram\_role\_name](#output\_ram\_role\_name) | Name of the RAM role the alibabaECI provider authenticates as (empty when enable\_ram\_role = false) |
<!-- END_TF_DOCS -->
