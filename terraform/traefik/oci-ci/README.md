# traefik/oci-ci

Traefik Hub as one OCI Container Instance — the OCI sibling of `traefik/aci` and a **multicluster CHILD**: it joins a Hub parent over a `:9443` uplink and discovers local whoami container instances via its own `hub.providers.ociContainerInstances` provider.

Composes `traefik/shared` (extracted Helm config) exactly like `traefik/aci`: the Hub image (`ghcr.io/zalbiraw/traefik-hub` via `custom_image_*`; the ocici provider ships only there) runs with `command = ["/traefik-hub"]` and the token + extracted args as `arguments` (exec'd with no shell, so the token is inlined). The Hub image is scratch — **CONFIGFILE volumes** (OCI's secret-volume mechanism) carry the file-provider config (and, with resource-principal auth off, the OCI credentials).

**Auth — resource principals, keyless by default:** container instances inject *resource-principal* credentials, and the ocici provider consumes them via `--hub.providers.ociContainerInstances.useResourcePrincipal=true`. `enable_resource_principal` (default on) creates a dynamic group matching the compartment's container instances plus a read-only policy (`read compute-container-family` / `read virtual-network-family` in the compartment) — the `security/oci-instance-principal` shape for container instances. Dynamic groups are tenancy-level, so it needs `tenancy_id` and IAM rights; both resources are named `<name>-resource-principal` off `var.name`, so two instantiations only collide if they share the same name. Disable the toggle to fall back to **config-file auth**: pass `oci_config` (an `~/.oci` style config whose `key_file` points inside the mount, e.g. `/etc/oci/key.pem`) + `oci_private_key`, delivered as a CONFIGFILE volume with `--hub.providers.ociContainerInstances.configFilePath` pointing at it. `ocici_provider.use_instance_principal` does **not** work on container instances (no IMDS flow) and is mutually exclusive with the resource-principal toggle (the gateway rejects combining the flags).

**Workload config note:** the ocici provider reads Traefik labels from **freeform tags** with dotted keys, exactly like `traefik/aci`'s Azure tags. Port precedence: port tag > NSG discovery (opt-in) > lowest declared container port (carried by health checks). Container instances have no "published port" list — `:9443` reachability is governed by the subnet's security lists/NSGs (OKE's demo security list allows all intra-VCN).

## Example usage

```hcl
module "oci_ci_traefik" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/oci-ci?ref=v5.4.3"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  compartment_id = var.compartment_id
  # Keyless provider auth (resource principal, the default) — the dynamic
  # group lives in the tenancy.
  tenancy_id = var.tenancy_id
  subnet_id  = module.oke.nodes_subnet_id

  # The ocici provider isn't in a Hub release — run the custom image.
  enable_preview_mode     = true
  custom_image_registry   = "docker.io"
  custom_image_repository = "zalbiraw/traefik-hub"
  custom_image_tag        = "latest"

  # Hub uplink entrypoint on :9443 (TLS; the parent verifies with insecureSkipVerify).
  multicluster_provider = { enabled = true }
  custom_ports = {
    ociciuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }

  # Advertise the provider-discovered service over the uplink (same shape as traefik/aci).
  file_provider_config = yamlencode({
    http = {
      uplinks = { ocici-whoami = { entryPoints = ["ociciuplink"] } }
      routers = {
        ocici-whoami = {
          rule    = "PathPrefix(`/`)"
          service = "whoami@ocici"
          uplinks = ["ocici-whoami"]
        }
      }
    }
  })
}
```

## Prerequisites

- OCI credentials with Container Instances/Network permissions and an existing compartment, plus tenancy-level **IAM rights** (dynamic group + policy) for the default resource-principal auth — or set `enable_resource_principal = false` and pass an API signing key (`oci_config`/`oci_private_key`) instead.
- A joinable subnet; `:9443` must be reachable in-VCN (e.g. `compute/oracle/oke`'s `nodes_subnet_id`).
- `helm` on the machine running terraform (`traefik/shared` extracts config via `helm template`).

## Notes

- One container instance — the parent dials `values(module.oci_ci_traefik.private_ips)[0]` on `:9443` (also exposed flat as `ip_address`).
- `enable_dashboard_discovery = false` when the dashboard is advertised via a file-rule uplink (same cleanup as the ACI spoke).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [null_resource.resource_principal_bounce](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.resource_principal_dynamic_group](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.resource_principal_policy](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [terraform_data.auth_guard](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | OCID of the compartment the container instance is created in (also the ociContainerInstances provider's default discovery scope) | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | OCID of the existing subnet the container instance VNIC joins (the parent dials the instance's private IP :9443 in-VCN, e.g. compute/oracle/oke's nodes\_subnet\_id) | `string` | n/a | yes |
| <a name="input_availability_domain"></a> [availability\_domain](#input\_availability\_domain) | Availability domain the container instance is placed in. Empty = the compartment's first AD (same pick as compute/oracle/oke). | `string` | `""` | no |
| <a name="input_base_config"></a> [base\_config](#input\_base\_config) | The ociContainerInstances provider's base configuration (YAML) for the OFFLINE filename path: the services the discovered IPs merge into, plus routers/uplinks. Delivered as a CONFIGFILE volume mounted at dirname(ocici\_provider.filename); set ocici\_provider.filename to the in-container path. Unused (leave empty) when ocici\_provider.config\_endpoint serves the base configuration instead. | `string` | `""` | no |
| <a name="input_container_memory_in_gbs"></a> [container\_memory\_in\_gbs](#input\_container\_memory\_in\_gbs) | Memory (GB) for the Traefik container instance | `number` | `4` | no |
| <a name="input_container_ocpus"></a> [container\_ocpus](#input\_container\_ocpus) | OCPUs for the Traefik container instance (1 OCPU = 2 vCPUs on E4.Flex) | `number` | `1` | no |
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
| <a name="input_enable_dashboard_discovery"></a> [enable\_dashboard\_discovery](#input\_enable\_dashboard\_discovery) | Self-register the Traefik container instance via freeform tags (traefik.enable + dashboard router/service) so its OWN ociContainerInstances provider discovers the dashboard as dashboard@ocici. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the instance isn't self-discovered at all. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_enable_resource_principal"></a> [enable\_resource\_principal](#input\_enable\_resource\_principal) | Authenticate the ociContainerInstances provider as a RESOURCE principal (useResourcePrincipal=true) — keyless: creates a dynamic group matching the compartment's container instances plus a read-only policy, both named `<name>-resource-principal` (requires tenancy\_id and IAM rights; two same-name instantiations collide). Disable to fall back to the oci\_config/oci\_private\_key config-file volume. | `bool` | `true` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra freeform tags to apply to the container instance | `map(string)` | `{}` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik/dynamic"` | no |
| <a name="input_home_region"></a> [home\_region](#input\_home\_region) | Tenancy home region identifier (e.g. us-ashburn-1). OCI IAM writes only succeed against the home region, so the resource-principal dynamic group + policy are created there via the OCI CLI. Required when enable\_resource\_principal = true. | `string` | `""` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Traefik container instance | `string` | `"traefik"` | no |
| <a name="input_nsg_ids"></a> [nsg\_ids](#input\_nsg\_ids) | Network security group OCIDs to attach to the container instance VNIC | `list(string)` | `[]` | no |
| <a name="input_oci_config"></a> [oci\_config](#input\_oci\_config) | Content of an ~/.oci style config file — the ociContainerInstances provider's config-file credential, mounted as a CONFIGFILE volume at the directory of ocici\_provider.config\_file\_path. Its key\_file MUST point inside that mount (e.g. /etc/oci/key.pem). Required (with oci\_private\_key) when enable\_resource\_principal = false; unused otherwise. | `string` | `""` | no |
| <a name="input_oci_private_key"></a> [oci\_private\_key](#input\_oci\_private\_key) | PEM content of the API signing key the oci\_config references (mounted as key.pem next to it). Required when enable\_resource\_principal = false; unused otherwise. | `string` | `""` | no |
| <a name="input_ocici_provider"></a> [ocici\_provider](#input\_ocici\_provider) | Traefik Hub ociContainerInstances provider configuration (hub.providers.ociContainerInstances). compartment\_id defaults to the module's compartment\_id. Auth defaults to resource principal (enable\_resource\_principal); use\_instance\_principal is an escape hatch that doesn't work on container instances (no IMDS flow) and is mutually exclusive with it. The base configuration (the services — with port/strategy/health checks — that discovered IPs merge into, plus any routers/uplinks) comes from config\_endpoint (a GitOps URL the provider polls, e.g. the hub's git-config-server) OR filename (a CONFIGFILE volume baked into the instance via base\_config — forces instance replacement on every config change, offline use only). Exactly one when enabled: this provider cannot boot without a base configuration. | <pre>object({<br/>    enabled                = optional(bool, true)<br/>    compartment_id         = optional(string, "")<br/>    region                 = optional(string, "")<br/>    use_instance_principal = optional(bool, false)<br/>    config_file_path       = optional(string, "/etc/oci/config")<br/>    ip_mode                = optional(string, "private")<br/>    # GitOps URL the provider polls for the base config — the mechanism that<br/>    # makes a routing-intent change a config push, not an instance replacement.<br/>    config_endpoint             = optional(string, "")<br/>    config_insecure_skip_verify = optional(bool, false)<br/>    # Offline alternative: a base-config file in the container (delivered as a<br/>    # CONFIGFILE volume from var.base_config). Mutually exclusive with<br/>    # config_endpoint.<br/>    filename             = optional(string, "")<br/>    service_name_tag_key = optional(string, "TraefikServiceName")<br/>    refresh_seconds      = optional(number, null)<br/>  })</pre> | `{}` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_shape"></a> [shape](#input\_shape) | Container instance shape (flex shapes are sized by container\_ocpus/container\_memory\_in\_gbs) | `string` | `"CI.Standard.E4.Flex"` | no |
| <a name="input_tenancy_id"></a> [tenancy\_id](#input\_tenancy\_id) | OCID of the tenancy — where the resource-principal dynamic group is created (dynamic groups are tenancy-level). Required when enable\_resource\_principal = true. | `string` | `""` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_instance_id"></a> [container\_instance\_id](#output\_container\_instance\_id) | OCID of the Traefik container instance |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | Private VNIC IP of the Traefik container instance (the parent dials https://<ip>:9443) |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance name to private IP (mirrors traefik/oci-vm's consumption shape: values(...)[0]) |
<!-- END_TF_DOCS -->
