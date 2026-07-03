# traefik/ibm-vpc

Provisions Traefik Hub on an IBM Cloud VPC virtual server instance — the multicluster CHILD on IBM, sibling of `traefik/ec2` / `traefik/oci-vm` / `traefik/alibaba-ecs`. Composes `traefik/shared` (extracted CLI args/env via Helm template) and the `traefik/cloud-init` template; the Hub image runs as a docker container in preview mode (the `ibmVPC` provider ships in preview builds).

> **New provider**: this is one of the repo's first IBM Cloud modules and introduces the `IBM-Cloud/ibm` Terraform provider (pinned `~> 1.89`).

## How the ibmVPC provider differs from the other VM providers

- **One credential, two flows.** Either an IAM API key (`ibmcloud_api_key` → `--hub.providers.ibmVPC.apiKey`) or — **keyless** — an IAM **trusted profile** (`trusted_profile_id` → `--hub.providers.ibmVPC.trustedProfileID`): the provider exchanges the VSI's instance-metadata identity token for an IAM token via the profile (the IBM SDK `VpcInstanceAuthenticator`). The two are mutually exclusive (a precondition enforces the XOR). For the trusted-profile flow the module enables the VSI **metadata service** (`metadata_service { enabled = true }`, off by default on IBM); the caller creates the profile, links the VSI (`ibm_iam_trusted_profile_link`, `cr_type "VSI"`, `link.crn` = this module's `instance_crn` output) and grants the profile Viewer on VPC Infrastructure Services (`is`) + Global Search & Tagging (`global-search-tagging`).
- **No per-instance `traefik.*` config.** IBM user tags are flat strings, so routers/services/middlewares live in a **base configuration file** (`base_config_content`). The module ships it to the VM via the cloud-init `extra_files` transport (the same `write_files` mechanism `traefik/ec2` uses for the file-provider config, different target path: `base_config_path`, default `/data/traefik-hub/ibmvpc.yaml` — under `/data` so the preview-mode container sees it, and deliberately **not** under `/etc/traefik-hub/dynamic`, which the file provider watches and would double-load). The provider fills each service's `servers` with the instances tagged `traefik-service-name:<service>` (one Global Search query) and fsnotify-watches the file for hot reloads.
- **No tag-based dashboard self-discovery** — advertise the dashboard via `file_provider_config` (file rule) instead, like the serverless children do.

## Example usage

```hcl
module "traefik_ibm_vpc" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/traefik/ibm-vpc?ref=v4.3.0"

  subnet_id          = module.vpc.subnet_id
  security_group_ids = module.vpc.security_group_ids

  enable_api_gateway  = true
  enable_preview_mode = true # ibmVPC ships in preview builds
  traefik_hub_token   = var.traefik_hub_token
  ibmcloud_api_key    = var.ibmcloud_api_key

  # Routers/services for the tagged whoami VMs (apps/whoami/ibm-vpc);
  # the provider fills whoami's servers from the instance tags.
  base_config_content = <<-EOT
    http:
      routers:
        whoami:
          rule: PathPrefix(`/`)
          service: whoami
      services:
        whoami:
          loadBalancer: {}
  EOT

  # The multicluster uplink entrypoint the parent dials (:9443, in-VPC).
  custom_ports = {
    uplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }
}

# Parent side: children dial https://<private-ip>:9443
# values(module.traefik_ibm_vpc.private_ips)[0]
```

## Prerequisites

- A provider-discovery credential: an IBM Cloud API key with VPC + Global Search reader access, **or** an IAM trusted profile (linked to this VSI, same reader roles) for the keyless path. Terraform itself needs VPC write access (plus IAM Identity rights if it manages the trusted profile); the region comes from the configured `ibm` provider.
- An existing subnet + security group (e.g. `compute/ibm/vpc`'s: opens 80/443/8080/22 + :9443 in-VPC, attaches a public gateway for image pulls, and allows egress).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_ibm"></a> [ibm](#requirement\_ibm) | ~> 1.89 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_ibm"></a> [ibm](#provider\_ibm) | ~> 1.89 |

## Resources

| Name | Type |
|------|------|
| [ibm_is_floating_ip.traefik](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_floating_ip) | resource |
| [ibm_is_instance.traefik](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_instance) | resource |
| [ibm_is_security_group.traefik](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_security_group) | resource |
| [ibm_is_security_group_rule.egress](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_security_group_rule) | resource |
| [ibm_is_security_group_rule.ingress](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_security_group_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the existing subnet the instance joins (the parent dials the instance's private IP :9443 in-VPC, e.g. compute/ibm/vpc's subnet\_id). The zone, VPC and default provider region derive from it. | `string` | n/a | yes |
| <a name="input_base_config_content"></a> [base\_config\_content](#input\_base\_config\_content) | The ibmVPC provider's BASE CONFIGURATION file content (YAML routers/services/middlewares). REQUIRED when the provider is enabled — instances carry only a '<serviceNameTagKey>:<service>' tag, and the provider fills each service's servers with the tagged instances' IPs. Shipped to the VM at base\_config\_path via cloud-init and hot-reloaded on change (fsnotify). | `string` | `""` | no |
| <a name="input_base_config_path"></a> [base\_config\_path](#input\_base\_config\_path) | Path on the VM the base configuration file is written to and the provider reads it from (--hub.providers.ibmVPC.filename). Keep it under /data (mounted into the preview-mode container) and OUT of /etc/traefik-hub/dynamic (the file provider watches that directory and would double-load the routers). | `string` | `"/data/traefik-hub/ibmvpc.yaml"` | no |
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
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_floating_ip"></a> [enable\_floating\_ip](#input\_enable\_floating\_ip) | Attach a floating IP to the instance (inbound access only — public entrypoints / dashboard). Off by default: the parent dials the private IP (same VPC), and image pulls ride the subnet's public gateway. | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. ibmVPC) | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_enable_security_group"></a> [enable\_security\_group](#input\_enable\_security\_group) | Create a security group opening security\_group\_ingress\_ports to the instance from security\_group\_source\_cidr, plus allow-all egress (mirrors traefik/alibaba-ecs's enable\_security\_group). Off by default — compute/ibm/vpc's group already opens the demo ports. | `bool` | `false` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the instance at cloud-init time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra user tags (flat strings) to apply to the instance | `list(string)` | `[]` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_ibmcloud_api_key"></a> [ibmcloud\_api\_key](#input\_ibmcloud\_api\_key) | IBM Cloud IAM API key the ibmVPC provider authenticates with (--hub.providers.ibmVPC.apiKey). Mutually exclusive with trusted\_profile\_id — set exactly one when the provider is enabled. Scope the key to VPC + Global Search reader roles. | `string` | `""` | no |
| <a name="input_ibmvpc_provider"></a> [ibmvpc\_provider](#input\_ibmvpc\_provider) | Traefik Hub ibmVPC provider configuration (hub.providers.ibmVPC). region and vpc\_id default to the joined subnet's region/VPC; endpoint/search\_endpoint default to the regional/global ones; service\_name\_tag\_key defaults to the provider's own default (traefik-service-name); poll\_interval is a duration string (provider default 30s). ipv6 ip\_mode yields nothing on VPC. Credentials come from var.ibmcloud\_api\_key; the base configuration file from var.base\_config\_content. | <pre>object({<br/>    enabled              = optional(bool, true)<br/>    region               = optional(string, "")<br/>    endpoint             = optional(string, "")<br/>    search_endpoint      = optional(string, "")<br/>    vpc_id               = optional(string, "")<br/>    service_name_tag_key = optional(string, "")<br/>    ip_mode              = optional(string, "private")<br/>    poll_interval        = optional(string, "")<br/>  })</pre> | `{}` | no |
| <a name="input_image_id"></a> [image\_id](#input\_image\_id) | Boot image ID. Empty = latest stock Ubuntu 24.04 amd64 image. | `string` | `""` | no |
| <a name="input_instance_profile"></a> [instance\_profile](#input\_instance\_profile) | VSI profile (default: 2 vCPU / 4 GB — the smallest VPC gen2 compute profile) | `string` | `"cx2-2x4"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource group ID the instance and network resources land in. Empty = the account's default resource group. | `string` | `""` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Existing security group IDs to attach to the instance (e.g. compute/ibm/vpc's security\_group\_ids). IBM security groups deny both directions by default — the attached groups must allow the demo ports in and image pulls out. | `list(string)` | `[]` | no |
| <a name="input_security_group_ingress_ports"></a> [security\_group\_ingress\_ports](#input\_security\_group\_ingress\_ports) | TCP ports the module-created security group opens on the instance. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials. | `list(number)` | <pre>[<br/>  80,<br/>  443,<br/>  8080,<br/>  9443<br/>]</pre> | no |
| <a name="input_security_group_source_cidr"></a> [security\_group\_source\_cidr](#input\_security\_group\_source\_cidr) | Source CIDR the module-created security group allows. Default covers RFC1918 VPCs (compute/ibm/vpc's VPC is 10.0.0.0/16). | `string` | `"10.0.0.0/8"` | no |
| <a name="input_ssh_key_ids"></a> [ssh\_key\_ids](#input\_ssh\_key\_ids) | IBM Cloud SSH key IDs to inject (debugging convenience) | `list(string)` | `[]` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |
| <a name="input_trusted_profile_id"></a> [trusted\_profile\_id](#input\_trusted\_profile\_id) | IAM trusted profile ID the ibmVPC provider authenticates with (--hub.providers.ibmVPC.trustedProfileID) — the KEYLESS path: the provider exchanges the VSI's instance-metadata identity token for an IAM token via the profile (VpcInstanceAuthenticator). Mutually exclusive with ibmcloud\_api\_key. The module enables the VSI metadata service when set; the caller links the VSI to the profile (ibm\_iam\_trusted\_profile\_link, cr\_type "VSI") and grants the profile the reader policies (Viewer on is + global-search-tagging). | `string` | `""` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the Traefik instance and its network resources | `string` | `"traefik"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instance_crn"></a> [instance\_crn](#output\_instance\_crn) | CRN of the Traefik virtual server instance — what an ibm\_iam\_trusted\_profile\_link (cr\_type "VSI") links for the keyless trusted-profile flow |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | ID of the Traefik virtual server instance |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1) |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their floating IP addresses (empty string when enable\_floating\_ip = false) |
<!-- END_TF_DOCS -->
