# traefik/azure-vm

Traefik Hub on one Azure Linux VM — the Azure sibling of `traefik/ec2` and a **multicluster CHILD**: it joins a Hub parent over a `:9443` uplink and discovers local whoami VMs via its own `hub.providers.azureVM` provider.

Composes `traefik/shared` (extracted Helm config) and `traefik/cloud-init` exactly like `traefik/ec2`. The azureVM provider ships only in a preview image (`ghcr.io/zalbiraw/traefik-hub`), so the demo sets `enable_preview_mode = true` + `custom_image_*` and the VM runs the image as a docker container (`--network host`, so IMDS/managed-identity and the uplink work).

Auth is the VM's **system-assigned managed identity** (DefaultAzureCredential) + a `Reader` role assignment scoped to the resource group — no client secret. The module appends the provider flags (`--hub.providers.azurevm.subscriptionID/resourceGroup/ipMode/exposedByDefault/...`) to `custom_arguments`; `subscription_id` defaults from `data.azurerm_client_config`.

## Example usage

```hcl
module "azure_vm_traefik" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/azure-vm?ref=v5.3.0"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  resource_group_name = azurerm_resource_group.demo.name
  subnet_id           = module.vnet.vm_subnet_id

  # The azureVM provider isn't in a Hub release — run the custom image as a container.
  enable_preview_mode     = true
  custom_image_registry   = "docker.io"
  custom_image_repository = "zalbiraw/traefik-hub"
  custom_image_tag        = "latest"

  # Hub uplink entrypoint on :9443 (TLS; the parent verifies with insecureSkipVerify).
  multicluster_provider = { enabled = true }
  custom_ports = {
    azurevmuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }

  # Advertise the provider-discovered service over the uplink (same shape as traefik/ec2).
  file_provider_config = yamlencode({
    http = {
      uplinks = { azure-vm-whoami = { entryPoints = ["azurevmuplink"] } }
      routers = {
        azure-vm-whoami = {
          rule    = "PathPrefix(`/`)"
          service = "whoami@azurevm"
          uplinks = ["azure-vm-whoami"]
        }
      }
    }
  })
}
```

## Prerequisites

- Azure credentials with Compute/Network permissions **and role-assignment rights** on the resource group (or set `enable_reader_role = false` and assign `Reader` yourself).
- An existing subnet (e.g. `compute/azure/vnet`'s `vm_subnet_id`); `:9443` must be reachable in-vnet (Azure's default NSG rules allow intra-vnet traffic; `compute/azure/vnet` also opens it via `extra_ingress_ports = [9443]`).
- `helm` on the machine running terraform (`traefik/shared` extracts config via `helm template`).

## Notes

- One VM (no replica set) — the parent dials `values(module.azure_vm_traefik.private_ips)[0]` on `:9443`.
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

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_role_assignment.reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [null_resource.identity_bounce](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the VM is created in (also the azureVM provider's default discovery scope) | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the existing subnet the VM NIC joins (the parent dials the VM's private IP :9443 in-vnet) | `string` | n/a | yes |
| <a name="input_admin_password"></a> [admin\_password](#input\_admin\_password) | Admin password on the VM. Default satisfies Azure's complexity rules; demo-grade only. | `string` | `"TopSecretPassword1!"` | no |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Admin username on the VM (the cloud-init also creates the demo `traefiker` user) | `string` | `"azureuser"` | no |
| <a name="input_azurevm_provider"></a> [azurevm\_provider](#input\_azurevm\_provider) | Traefik Hub azureVM provider configuration (hub.providers.azureVM). subscription\_id defaults to the caller's (data.azurerm\_client\_config); resource\_group defaults to resource\_group\_name. No client credentials: DefaultAzureCredential resolves the VM's system-assigned managed identity. | <pre>object({<br/>    enabled            = optional(bool, true)<br/>    subscription_id    = optional(string, "")<br/>    resource_group     = optional(string, "")<br/>    ip_mode            = optional(string, "private")<br/>    exposed_by_default = optional(bool, false)<br/>    default_rule       = optional(string, "")<br/>    constraints        = optional(string, "")<br/>    refresh_seconds    = optional(number, null)<br/>    nsg_port_discovery = optional(bool, false)<br/>  })</pre> | `{}` | no |
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
| <a name="input_enable_dashboard_discovery"></a> [enable\_dashboard\_discovery](#input\_enable\_dashboard\_discovery) | Self-register the Traefik VM via tags (traefik.enable + dashboard router/service) so its OWN azureVM provider discovers the dashboard as dashboard@azurevm. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the VM isn't self-discovered at all. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_network_security_group"></a> [enable\_network\_security\_group](#input\_enable\_network\_security\_group) | Associate network\_security\_group\_id with the VM NIC. A separate config-known toggle because count cannot depend on the id when it is created in the same run. | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. azureVM) | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Attach a public IP to the VM. Off by default — the parent dials the private IP (same VNet). | `bool` | `false` | no |
| <a name="input_enable_reader_role"></a> [enable\_reader\_role](#input\_enable\_reader\_role) | Assign the Reader role on the provider's resource group to the VM's system-assigned identity (requires the caller to hold role-assignment rights, e.g. Owner/User Access Administrator). | `bool` | `true` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the VM at cloud-init time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra tags to apply to the VM | `map(string)` | `{}` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure location | `string` | `"eastus"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_network_security_group_id"></a> [network\_security\_group\_id](#input\_network\_security\_group\_id) | NSG ID to associate with the VM NIC (used only when enable\_network\_security\_group = true; may be a same-run resource attribute). Subnet-level NSG rules still apply either way; intra-vnet traffic to :9443 is allowed by Azure's default rules. | `string` | `""` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
| <a name="input_private_ip"></a> [private\_ip](#input\_private\_ip) | Fixed private IP for the gateway NIC (Static allocation). Must sit in subnet\_id's CIDR outside Azure's reserved first-4/last-1 hosts. Pinning it makes the hub's uplink dial address plan-known (no two-pass PENDING apply) and stable across VM recreation (the hub never dials a stale IP). Empty = Dynamic. | `string` | `""` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt. | `string` | `""` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the Traefik VM and its network resources | `string` | `"traefik"` | no |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | Azure VM size | `string` | `"Standard_B2s"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1) |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | Principal ID of the VM's system-assigned managed identity (the azureVM provider's credential) |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their public IP addresses (empty string when enable\_public\_ip = false) |
<!-- END_TF_DOCS -->
