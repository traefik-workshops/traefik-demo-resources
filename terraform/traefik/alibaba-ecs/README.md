# traefik/alibaba-ecs

Traefik Hub on an Alibaba Cloud ECS instance — the multicluster **child** on Alibaba, mirroring `traefik/azure-vm` and `traefik/oci-vm`. One instance runs the Hub image as a docker container (the `traefik/cloud-init` preview-image path) with the `hub.providers.alibabaECS` provider enabled, discovering workloads from dotted `traefik.*` tags on ECS instances (e.g. `apps/whoami/alibaba-ecs`). The parent cluster dials the instance's private IP on `:9443` (the Hub multicluster uplink).

**Keyless auth**: the module creates an instance RAM role (trusted by `ecs.aliyuncs.com`) with a read-only `ecs:Describe*` policy and attaches it (`enable_ram_role`, default on). The provider's empty-credential default chain (env → profile → RAM role via the 100.100.100.200 metadata endpoint) picks it up — no access keys on the VM.

## Example usage

```hcl
module "traefik_alibaba_ecs" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/alibaba-ecs?ref=v6.4.0"

  vswitch_id         = module.vpc.vswitch_id
  security_group_ids = module.vpc.security_group_ids

  traefik_hub_token   = var.traefik_hub_token
  enable_preview_mode = true # alibabaECS ships in preview builds

  # The uplink entrypoint the multicluster parent dials.
  custom_ports = {
    uplink = { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } }
  }
}

# On the parent:
#   children = { alibaba = { url = "https://${values(module.traefik_alibaba_ecs.private_ips)[0]}:9443" } }
```

## Prerequisites

- Alibaba Cloud credentials with ECS/VPC/RAM permissions; the region comes from the configured `alicloud` provider.
- An existing vswitch + security group opening `:9443` in-VPC (`compute/alibaba/vpc` does by default).
- A Hub license token with multicluster.

## Notes

- Provider flags delivered as CLI args: `--hub.providers.alibabaECS.regionID/.endpoint/.ipMode/.exposedByDefault/.defaultRule/.constraints/.refreshSeconds/.securityGroupPortDiscovery`.
- Per-instance IP-mode override on workloads: the `traefik.alibabaecs.ipmode` tag.
- RAM role/policy names derive from `vm_name` and are account-global — flip `enable_ram_role` off when they already exist.
- Docker pulls need outbound internet: `enable_public_ip = true` or a NAT gateway on the vswitch.

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
| <a name="module_compute"></a> [compute](#module\_compute) | ../../compute/alibaba/ecs | n/a |
| <a name="module_config"></a> [config](#module\_config) | ../shared | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [alicloud_ecs_ram_role_attachment.traefik](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/ecs_ram_role_attachment) | resource |
| [alicloud_ram_policy.traefik](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/ram_policy) | resource |
| [alicloud_ram_role.traefik](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/ram_role) | resource |
| [alicloud_ram_role_policy_attachment.traefik](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/ram_role_policy_attachment) | resource |
| [alicloud_regions.current](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/data-sources/regions) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_vswitch_id"></a> [vswitch\_id](#input\_vswitch\_id) | ID of the existing vswitch the instance joins (the parent dials the instance's private IP :9443 in-VPC, e.g. compute/alibaba/vpc's vswitch\_id) | `string` | n/a | yes |
| <a name="input_alibabaecs_provider"></a> [alibabaecs\_provider](#input\_alibabaecs\_provider) | Traefik Hub alibabaECS provider configuration (hub.providers.alibabaECS). region\_id defaults to the instance's own region (from the alicloud provider); endpoint defaults to the regional one. No access keys: empty credentials make the provider fall through the default chain (env -> profile -> instance RAM role via metadata — see enable\_ram\_role). | <pre>object({<br/>    enabled                       = optional(bool, true)<br/>    region_id                     = optional(string, "")<br/>    endpoint                      = optional(string, "")<br/>    ip_mode                       = optional(string, "private")<br/>    exposed_by_default            = optional(bool, false)<br/>    default_rule                  = optional(string, "")<br/>    constraints                   = optional(string, "")<br/>    refresh_seconds               = optional(number, null)<br/>    security_group_port_discovery = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_custom_arguments"></a> [custom\_arguments](#input\_custom\_arguments) | Additional CLI arguments for Traefik | `list(string)` | `[]` | no |
| <a name="input_custom_envs"></a> [custom\_envs](#input\_custom\_envs) | Custom environment variables | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_custom_image_registry"></a> [custom\_image\_registry](#input\_custom\_image\_registry) | Custom image registry | `string` | `""` | no |
| <a name="input_custom_image_repository"></a> [custom\_image\_repository](#input\_custom\_image\_repository) | Custom image repository | `string` | `""` | no |
| <a name="input_custom_image_tag"></a> [custom\_image\_tag](#input\_custom\_image\_tag) | Custom image tag | `string` | `""` | no |
| <a name="input_custom_plugins"></a> [custom\_plugins](#input\_custom\_plugins) | Custom plugins to use for the deployment | <pre>map(object({<br/>    moduleName = string<br/>    version    = string<br/>  }))</pre> | `{}` | no |
| <a name="input_custom_ports"></a> [custom\_ports](#input\_custom\_ports) | Custom ports configuration. Typed `any` so it can carry a full Helm `ports.<name>` shape — e.g. a Hub multicluster uplink entrypoint { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } } — not just { port, protocol }. | `any` | `{}` | no |
| <a name="input_dashboard_entrypoints"></a> [dashboard\_entrypoints](#input\_dashboard\_entrypoints) | Dashboard entry points | `list(string)` | <pre>[<br/>  "traefik"<br/>]</pre> | no |
| <a name="input_dashboard_insecure"></a> [dashboard\_insecure](#input\_dashboard\_insecure) | Enable insecure dashboard access (no auth) | `bool` | `true` | no |
| <a name="input_dashboard_match_rule"></a> [dashboard\_match\_rule](#input\_dashboard\_match\_rule) | Match rule for the Traefik dashboard router | `string` | `""` | no |
| <a name="input_enable_access_logs"></a> [enable\_access\_logs](#input\_enable\_access\_logs) | Enable Traefik access logs | `bool` | `true` | no |
| <a name="input_enable_ai_gateway"></a> [enable\_ai\_gateway](#input\_enable\_ai\_gateway) | Enable Traefik Hub AI Gateway features | `bool` | `false` | no |
| <a name="input_enable_api_gateway"></a> [enable\_api\_gateway](#input\_enable\_api\_gateway) | Enable Traefik Hub API Gateway features | `bool` | `false` | no |
| <a name="input_enable_dashboard"></a> [enable\_dashboard](#input\_enable\_dashboard) | Enable Traefik dashboard | `bool` | `true` | no |
| <a name="input_enable_dashboard_discovery"></a> [enable\_dashboard\_discovery](#input\_enable\_dashboard\_discovery) | Self-register the Traefik instance via tags (traefik.enable + dashboard router/service) so its OWN alibabaECS provider discovers the dashboard as dashboard@alibabaecs. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the instance isn't self-discovered at all. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. alibabaECS) | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Allocate a public IP to the instance (Alibaba grants one when outbound bandwidth > 0). Off by default — the parent dials the private IP (same VPC); without it, docker pulls need a NAT gateway on the vswitch. | `bool` | `false` | no |
| <a name="input_enable_ram_role"></a> [enable\_ram\_role](#input\_enable\_ram\_role) | Create an instance RAM role (trusted by ecs.aliyuncs.com) + read-only ecs:Describe* policy and attach it — the alibabaECS provider's keyless credential via the default chain (env -> profile -> RAM role metadata). RAM names are account-global (derived from vm\_name); disable when the demo already created them. | `bool` | `true` | no |
| <a name="input_enable_security_group"></a> [enable\_security\_group](#input\_enable\_security\_group) | Create a security group opening security\_group\_ingress\_ports to the instance from security\_group\_source\_cidr (mirrors traefik/oci-vm's enable\_nsg). Off by default — compute/alibaba/vpc's group already opens the demo ports. Requires vpc\_id. | `bool` | `false` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the instance at cloud-init time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra tags to apply to the instance | `map(string)` | `{}` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_image_id"></a> [image\_id](#input\_image\_id) | Boot image ID. Empty = latest public Ubuntu 24.04 x64 image. | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | ECS instance type (default: 2 vCPU / 4 GB economy) | `string` | `"ecs.e-c1m2.large"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
| <a name="input_private_ip"></a> [private\_ip](#input\_private\_ip) | Fixed private IP for the gateway instance. Must sit in vswitch\_id's CIDR outside Alibaba's reserved first-3/last-1 hosts. Pinning it makes the hub's uplink dial address plan-known (no two-pass PENDING apply) and stable across instance recreation (the hub never dials a stale IP). Empty = DHCP. | `string` | `""` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Existing security group IDs to attach to the instance (Alibaba requires at least one unless enable\_security\_group is on, e.g. compute/alibaba/vpc's security\_group\_ids) | `list(string)` | `[]` | no |
| <a name="input_security_group_ingress_ports"></a> [security\_group\_ingress\_ports](#input\_security\_group\_ingress\_ports) | TCP ports the module-created security group opens on the instance. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials. | `list(number)` | <pre>[<br/>  80,<br/>  443,<br/>  8080,<br/>  9443<br/>]</pre> | no |
| <a name="input_security_group_source_cidr"></a> [security\_group\_source\_cidr](#input\_security\_group\_source\_cidr) | Source CIDR the module-created security group allows. Default covers RFC1918 VPCs (compute/alibaba/vpc's VPC is 10.0.0.0/16). | `string` | `"10.0.0.0/8"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt. | `string` | `""` | no |
| <a name="input_system_disk_category"></a> [system\_disk\_category](#input\_system\_disk\_category) | System disk category. ESSD Entry pairs with the economy (e-series) default instance type; switch to cloud\_essd for g/c families. | `string` | `"cloud_essd_entry"` | no |
| <a name="input_system_disk_size"></a> [system\_disk\_size](#input\_system\_disk\_size) | System disk size (GB) | `number` | `40` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the Traefik instance and its RAM/network resources | `string` | `"traefik"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC the module-created security group is created in. Only required when enable\_security\_group = true. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | ID of the Traefik ECS instance |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1) |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their public IP addresses (empty string when enable\_public\_ip = false) |
| <a name="output_ram_role_name"></a> [ram\_role\_name](#output\_ram\_role\_name) | Name of the instance RAM role the alibabaECS provider authenticates as (empty when enable\_ram\_role = false) |
<!-- END_TF_DOCS -->
