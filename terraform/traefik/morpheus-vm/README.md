# traefik/morpheus-vm

Traefik Hub on an **HPE Morpheus instance** (MVM — the KVM compute type of **VM Essentials / HVM** and full Morpheus) — the on-prem sibling of `traefik/ec2` / `traefik/azure-vm` / `traefik/vsphere-vm`. Provisions one `hpe_morpheus_instance` (on an MVM cloud; `config_hvm` carries the KVM placement) from an existing instance type/layout/plan, extracts its Traefik configuration from `traefik/shared` (via Helm template) and boots it with the shared `traefik/cloud-init` template — as a systemd binary, or as a docker container when `enable_preview_mode = true` (required while the `morpheus` provider isn't in a tagged Hub release).

## The morpheus provider

`var.morpheus_provider` renders `--hub.providers.morpheus.*` CLI flags. The gateway discovers workload instances by their **`traefik.*` instance tags** — dotted name/value pairs, the cloud-style label model (see `apps/whoami/morpheus`); `constraints` match Morpheus **labels** (as `label=true` pairs) plus a synthesized `name` pseudo-label — but the `HPE/hpe` terraform provider can't SET labels (`hpe_morpheus_instance` has no labels attribute as of v1.5.0), so apply them in the appliance. When no `server.port` label is set, the provider falls back to the **lowest port declared in the instance's connection info** (layout-declared) — set the label explicitly. `ipMode` `private` and `public` both resolve to an instance's primary connection address on-prem; `ipv6` picks the first IPv6 one; per-instance override via the `traefik.morpheus.ipmode` tag.

**Credentials are explicit** — the gateway's Init enforces **exactly one** auth method: `var.morpheus_access_token` (sensitive, **preferred** — mint it for a read-only user) OR `morpheus_provider.username` + `var.morpheus_password`. `endpoint` must be the **full appliance URL including the scheme** (Init rejects a bare host). The credential lands in the instance's bootstrap task and unit file — demo-grade; don't hand it an admin.

Routerless discovery (`default_rule = "{{/*routerless*/}}"`) works exactly like the EC2/Azure/vSphere siblings: instances land as services only, and routers come from file-provider rules.

## Bootstrap is a Morpheus provisioning workflow (read this)

The `HPE/hpe` terraform provider has **no user-data / cloud-config passthrough** on its instance resource (verified against the v1.5.0 schema; neither did gomorpheus), so the composed `traefik/cloud-init` payload is **converted in terraform** (`yamldecode`: `write_files` → heredocs, `runcmd` → tolerated sequential entries — cloud-init's own semantics) into a shell script delivered as an `hpe_morpheus_task_shell_script` in a `postProvision` `hpe_morpheus_workflow_provisioning`, executed by the **Morpheus agent**. Consequences: `config_hvm.no_agent` stays false (the provider default is agentless) and the layout must boot a **cloud-init-enabled Linux image**; config changes recreate the instance (`replace_triggered_by`); the template's `users`/`chpasswd` access conveniences are not applied; the task/workflow are appliance-level library items named `<vm_name>-traefik-bootstrap`.

## Example usage

```hcl
module "traefik_morpheus" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/morpheus-vm?ref=v5.2.1"

  cloud              = "hvm-cloud"
  group              = "demo"
  instance_type      = "Ubuntu"
  instance_layout    = "Single KVM VM"
  plan               = "2 CPU, 4GB Memory"
  resource_pool_name = "hvm-cluster-01"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  morpheus_provider = {
    endpoint = "https://morpheus.lab.example.com"
  }
  morpheus_access_token = var.morpheus_access_token # or username in the object + morpheus_password

  # Join a Hub mesh: uplink entrypoint on :9443, parent dials this instance's primary IP.
  multicluster_provider = { enabled = true }
  custom_ports = {
    vmuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }
}
```

## Prerequisites

- A Morpheus appliance (**VM Essentials / HVM** or full Morpheus) with an MVM cloud/group/instance type/layout/plan; terraform provider credentials allowed to create library tasks/workflows and provision instances — the gateway's read-only discovery credential can (and should) differ.
- A cloud-init-enabled Linux layout (agent-installable); DHCP on the network; `helm` on the machine running terraform (config extraction via `helm template`).

## Notes

- `enable_dashboard_discovery` (default on) self-registers the instance's dashboard through its own `traefik.*` tags (`dashboard@morpheus`); disable it when a file-rule uplink advertises the dashboard instead.
- Outputs mirror the VM siblings (`instances` / `private_ips` / `public_ips`) so demo code reads identically — on Morpheus both IP maps carry the same primary address.
- MIGRATED from the community-deprecated `gomorpheus/morpheus` provider (EOL Aug 2026) to the official `HPE/hpe` provider (`~> 1.5`). One functional loss: `hpe_morpheus_instance` has **no `labels` attribute** (v1.5.0), so `morpheus_labels` must stay empty (validated) — set Morpheus labels in the appliance instead. `plan_provision_type` is now the provision type **code** (`"kvm"`), not the name (`"KVM"`). State from gomorpheus deployments does not migrate — plan on recreating.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.gateway_provider_auth](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloud"></a> [cloud](#input\_cloud) | Name of the Morpheus cloud (e.g. the MVM/HVM cloud registered on the appliance) the instance is provisioned into | `string` | n/a | yes |
| <a name="input_group"></a> [group](#input\_group) | Name of the Morpheus group the instance belongs to | `string` | n/a | yes |
| <a name="input_instance_layout"></a> [instance\_layout](#input\_instance\_layout) | Name of the instance layout under instance\_type (e.g. "Single KVM VM") | `string` | n/a | yes |
| <a name="input_plan"></a> [plan](#input\_plan) | Name of the service plan — the plan IS the VM shape on Morpheus (no cpu/memory knobs here); pick one that fits a gateway (e.g. "2 CPU, 4GB Memory") | `string` | n/a | yes |
| <a name="input_resource_pool_name"></a> [resource\_pool\_name](#input\_resource\_pool\_name) | Name of the resource pool (the MVM/HVM cluster) to provision the instance to | `string` | n/a | yes |
| <a name="input_computed_placement_ids"></a> [computed\_placement\_ids](#input\_computed\_placement\_ids) | Passthrough to compute/morpheus/vm: set true when instance\_type\_id / instance\_layout\_id / resource\_pool\_id are supplied from apply-time values (they go unknown at destroy and break the name-lookup count with Invalid count argument). See that module's variable of the same name. | `bool` | `false` | no |
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
| <a name="input_enable_dashboard_discovery"></a> [enable\_dashboard\_discovery](#input\_enable\_dashboard\_discovery) | Self-register the Traefik instance via its own `traefik.*` tags (traefik.enable + dashboard router/service) so its OWN morpheus provider discovers the dashboard as dashboard@morpheus. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the instance isn't self-discovered at all. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. morpheus) | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_enable_provisioning_workflow"></a> [enable\_provisioning\_workflow](#input\_enable\_provisioning\_workflow) | Wrap the bootstrap task in a Morpheus PROVISIONING WORKFLOW (a task-set) and attach it to each instance via task\_set\_id — the native path, which runs the bootstrap at postProvision. Requires features.workflows: HPE VM Essentials does NOT have it (POST /api/task-sets -> 403 "Feature Not Included for the Applied License", and the 403 fires before body validation). Set FALSE on VME and execute the task DIRECTLY instead — POST /api/tasks/{id}/execute is ungated (it answers 404 for a bogus id, not 403), and the task resource itself is fine (features.tasks=true). When false the CALLER owns triggering the bootstrap after provisioning; the module exposes bootstrap\_task\_ids for exactly that. | `bool` | `true` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the instance at bootstrap time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_labels"></a> [extra\_labels](#input\_extra\_labels) | Extra Traefik labels merged into the instance's own `traefik.*` tags (on top of the dashboard self-registration labels, when enabled) | `map(string)` | `{}` | no |
| <a name="input_extra_runcmd"></a> [extra\_runcmd](#input\_extra\_runcmd) | Extra shell blocks appended to cloud-init runcmd, after Docker is installed and before traefik-hub starts. Used to run workload containers on the gateway VM itself (the docker-provider leg). | `list(string)` | `[]` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_instance_layout_id"></a> [instance\_layout\_id](#input\_instance\_layout\_id) | Literal layout id, bypassing the name lookup. REQUIRED on HPE VM Essentials (see instance\_type\_id). Also disambiguates: "Single KVM VM" is NOT unique — Ubuntu carries several. null = resolve by name. | `number` | `null` | no |
| <a name="input_instance_layout_version"></a> [instance\_layout\_version](#input\_instance\_layout\_version) | Version of the instance layout (e.g. "24.04") — disambiguates layouts sharing a name. Empty = match by name alone. | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Name of the Morpheus instance type to provision from (e.g. "Ubuntu"). Must boot a cloud-init-enabled Linux image — the Morpheus agent (installed via cloud-init) runs the Traefik bootstrap. | `string` | `"Ubuntu"` | no |
| <a name="input_instance_type_id"></a> [instance\_type\_id](#input\_instance\_type\_id) | Literal instance-type id, bypassing the name lookup. REQUIRED on HPE VM Essentials: the hpe\_morpheus\_instance\_type data source calls /api/library/instance-types, which 403s (templates=false) at PLAN time. null = resolve by name (full Morpheus, where the Library is licensed). | `number` | `null` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_morpheus_access_token"></a> [morpheus\_access\_token](#input\_morpheus\_access\_token) | Morpheus API access token the gateway's morpheus provider authenticates with (PREFERRED — mint it for a read-only user; discovery only lists instances). Empty = username/password auth via morpheus\_provider.username + morpheus\_password. | `string` | `""` | no |
| <a name="input_morpheus_labels"></a> [morpheus\_labels](#input\_morpheus\_labels) | MUST STAY EMPTY: the HPE/hpe provider's hpe\_morpheus\_instance exposes NO labels attribute (checked at v1.5.0; gomorpheus's morpheus\_mvm\_instance did), so Morpheus labels can't be applied from terraform anymore. The variable is kept (and validated empty) so existing callers passing [] keep working; set labels in the appliance instead. | `list(string)` | `[]` | no |
| <a name="input_morpheus_password"></a> [morpheus\_password](#input\_morpheus\_password) | Morpheus password for morpheus\_provider.username (the username/password alternative to morpheus\_access\_token). Point it at a READ-ONLY role — the credential lands in the instance's bootstrap task and unit file. | `string` | `""` | no |
| <a name="input_morpheus_provider"></a> [morpheus\_provider](#input\_morpheus\_provider) | Traefik Hub morpheus provider configuration (hub.providers.morpheus). Morpheus has no ambient identity, so credentials are explicit: an API access token (var.morpheus\_access\_token, PREFERRED) or username here + var.morpheus\_password — the gateway's Init enforces exactly one method. endpoint must be the full appliance URL INCLUDING the scheme (Init rejects a bare host); insecure\_skip\_verify defaults on (self-signed appliance certs are the norm); ipMode private/public both resolve to an instance's primary connection address on-prem. | <pre>object({<br/>    enabled              = optional(bool, true)<br/>    endpoint             = optional(string, "")<br/>    username             = optional(string, "")<br/>    insecure_skip_verify = optional(bool, true)<br/>    ip_mode              = optional(string, "private")<br/>    exposed_by_default   = optional(bool, false)<br/>    default_rule         = optional(string, "")<br/>    constraints          = optional(string, "")<br/>    refresh_seconds      = optional(number, null)<br/>  })</pre> | `{}` | no |
| <a name="input_mount_docker_socket"></a> [mount\_docker\_socket](#input\_mount\_docker\_socket) | Bind /var/run/docker.sock into the preview-mode Traefik container so its docker provider can reach the local daemon. Root-equivalent access to the host, so leave it off for any gateway that is not the docker-provider leg. | `bool` | `false` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_network"></a> [network](#input\_network) | Name of the Morpheus network the instance NIC joins (DHCP is assumed; the parent dials the instance's primary IP :9443 in-network). Empty = the layout's default network selection. | `string` | `""` | no |
| <a name="input_network_interface_type_id"></a> [network\_interface\_type\_id](#input\_network\_interface\_type\_id) | Morpheus network interface TYPE ID for the NIC (required when network is set) | `number` | `null` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
| <a name="input_plan_provision_type"></a> [plan\_provision\_type](#input\_plan\_provision\_type) | Provision type CODE the plan is looked up under (the hpe\_morpheus\_service\_plan data source filters by provision\_type\_code; "kvm" for MVM / HPE VM Essentials clouds — the gomorpheus-era value here was the NAME "KVM"). Empty = match the plan by name alone. | `string` | `"kvm"` | no |
| <a name="input_private_ip"></a> [private\_ip](#input\_private\_ip) | Fixed static IP for the gateway NIC. When set, the interface uses ip\_mode=static with this address (must sit in the joined network's range, outside the appliance's DHCP pool). Pinning it makes the hub's uplink dial address plan-known (no two-pass PENDING apply) and stable across instance recreation (the hub never dials a stale IP). Empty = DHCP (the appliance-reported primary IP). | `string` | `""` | no |
| <a name="input_resource_pool_id"></a> [resource\_pool\_id](#input\_resource\_pool\_id) | Literal resource-pool id, bypassing the name lookup. REQUIRED on HPE VM Essentials: it has no ResourcePool records (/api/resource-pools -> total=0) — the HVM cluster is a synthetic "pool-<clusterId>" served only by the zonePools option source, so the data source fails at PLAN time with "found 0 resourcePools". null = resolve by name (full Morpheus). | `string` | `null` | no |
| <a name="input_root_volume"></a> [root\_volume](#input\_root\_volume) | Optional explicit root volume {size (GB), datastore\_id, storage\_type, name}. null = the layout/plan defaults. | <pre>object({<br/>    size         = number<br/>    datastore_id = number<br/>    storage_type = optional(number, 1)<br/>    name         = optional(string, "root")<br/>  })</pre> | `null` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt. | `string` | `""` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the Traefik instance (also the prefix of the bootstrap task/workflow names — unique per appliance) | `string` | `"traefik"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bootstrap_task_ids"></a> [bootstrap\_task\_ids](#output\_bootstrap\_task\_ids) | Bootstrap shell-script task ids, by app. Only useful when enable\_provisioning\_workflow=false: the caller executes these itself via POST /api/tasks/{id}/execute with {"job":{"targetType":"instance","instances":[<id>]}} — the ungated path on HPE VM Essentials. |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1). private\_ip and public\_ip are the SAME primary connection address (connection\_info[0]) — on-prem Morpheus instances have one primary IP and no cloud public-IP concept (the provider's private/public ipModes both resolve to it). |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their primary IP addresses (the parent dials https://<ip>:9443) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their primary IP addresses — identical to private\_ips (no public-IP concept on-prem; kept for sibling-parity) |
<!-- END_TF_DOCS -->