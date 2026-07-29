# traefik/proxmox-vm

Traefik Hub on a **Proxmox VE VM** — the on-prem sibling of `traefik/vsphere-vm` / `traefik/ec2` / `traefik/azure-vm`. Clones a user-provided **cloud-init-enabled Ubuntu cloud-image template**, extracts its Traefik configuration from `traefik/shared` (via Helm template) and boots it with the shared `traefik/cloud-init` template — as a systemd binary, or as a docker container when `enable_preview_mode = true`.

## Discovery is the native first-party Hub Proxmox provider

Like `hub.providers.ec2` / `azureVM` / `gce`, discovery here is a **native first-party Hub provider** compiled into the Traefik Hub image — no Yaegi plugin download, no `experimental.plugins`. `var.proxmox_provider` renders its static config as `--hub.providers.proxmox.*` CLI flags:

```
--hub.providers.proxmox=true
--hub.providers.proxmox.endpoint=https://pve.example.com:8006
--hub.providers.proxmox.tokenID=traefik@pve!discovery
--hub.providers.proxmox.tokenSecret=***          # var.proxmox_api_token
--hub.providers.proxmox.insecureSkipVerify=true  # self-signed PVE certs are the lab norm
--hub.providers.proxmox.refreshSeconds=30
--hub.providers.proxmox.exposedByDefault=false
--hub.providers.proxmox.ipMode=private
--hub.providers.proxmox.guestTypes=qemu          # scope this gateway to one compute type
```

The provider is built into the Hub image, so nothing is downloaded at start — the VM needs no outbound internet to fetch a discovery plugin. Its dynamic config lands under the **`@proxmox`** provider namespace, so file-provider routers reference discovered services as `<name>@proxmox`.

What the provider does: polls the PVE API, reads each **running** QEMU VM's and LXC container's **Notes/description field line by line** for `traefik.key=value` labels (`traefik.enable=true` mandatory — see `apps/whoami/proxmox`), resolves guest IPs (QEMU guest agent for VMs; the lxc interfaces endpoint for containers), and emits routers + services. `guest_types` scopes a gateway to one compute type (`["qemu"]` or `["lxc"]`); `nodes` and `tag_filter` narrow it further — the filters the old NX211 plugin never had. Semantics to plan around:

- **One server per service, no merging** — same-named services on two guests overwrite each other. Compose multi-guest spreads with a `weighted` file-provider service.
- **No `loadbalancer.strategy` label** — supported service options are port/scheme/url/ip, passHostHeader, healthcheck, sticky cookie, responseForwarding, serversTransport.
- **Every enabled guest gets a router** (default rule ``Host(`<guest-name>`)``) — there is no routerless mode; expect harmless auto-routers next to your file-provider ones.

**Credentials are explicit** — Proxmox has no ambient identity, so the provider takes a **PVE API token** (`token_id` in `var.proxmox_provider`, the secret in `var.proxmox_api_token` → `--hub.providers.proxmox.tokenID`/`tokenSecret`). Create a read-only role: `VM.Audit,Sys.Audit,Datastore.Audit` plus `VM.GuestAgent.Audit` on PVE 9 (`VM.Monitor` on PVE 8). The token lands in the VM's systemd unit / container args — demo-grade; don't reuse an admin credential.

## Example usage

```hcl
module "traefik_proxmox" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/traefik/proxmox-vm?ref=v4.3.0"

  node_name     = "pve"
  datastore_id  = "local-lvm"
  template_name = "ubuntu-24.04-cloudimg"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  proxmox_provider = {
    endpoint    = "https://pve.lab.example.com:8006"
    token_id    = "traefik@pve!discovery"
    guest_types = ["qemu"]
  }
  proxmox_api_token = var.discovery_api_token

  # Join a Hub mesh: uplink entrypoint on :9443, parent dials this VM's guest IP.
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

- The `bpg/proxmox` provider with clone rights **and** its `ssh {}` block (the cloud-init snippet uploads over SSH) — plus the separate read-only discovery token above; they can differ.
- A **cloud-init-enabled Ubuntu cloud-image template with `qemu-guest-agent` baked in** (the agent reports the guest IP the parent dials — this module's user-data is the shared Traefik template, so it can't install the agent itself). DHCP on the bridge; `helm` on the machine running terraform (config extraction via `helm template`); outbound internet from the VM (Hub binary/image — the discovery provider is built in, nothing extra to download).

## Notes

- `enable_dashboard_discovery` (default on) self-registers the VM's dashboard through its own Notes labels (`dashboard` router on `@proxmox`); disable it when a file-rule uplink advertises the dashboard instead.
- Outputs mirror the VM siblings (`instances` / `private_ips` / `public_ips`) so demo code reads identically — on Proxmox both IP maps carry the same guest address.
- The cloud-init snippet is hash-named and the VM `replace_triggered_by`s it — config changes recreate the VM (cloud-init runs on first boot only).

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
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Datastore backing the VM's disk and cloud-init drive (e.g. local-lvm) | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Name of the Proxmox VE node the VM is created on | `string` | n/a | yes |
| <a name="input_proxmox_api_token"></a> [proxmox\_api\_token](#input\_proxmox\_api\_token) | PVE API token SECRET the native proxmox provider authenticates with (pairs with proxmox\_provider.token\_id → --hub.providers.proxmox.tokenSecret). Point it at a read-only role — VM.Audit,Sys.Audit,Datastore.Audit plus VM.GuestAgent.Audit on PVE 9 (VM.Monitor on PVE 8) for guest-agent IP reads. | `string` | n/a | yes |
| <a name="input_bridge"></a> [bridge](#input\_bridge) | Name of the Linux bridge the VM's NIC joins (DHCP is assumed; the parent dials the VM's guest IP :9443 in-network) | `string` | `"vmbr0"` | no |
| <a name="input_cpu_type"></a> [cpu\_type](#input\_cpu\_type) | QEMU CPU type. `host` passes the node's CPU through; pick a named model when live migration matters. | `string` | `"host"` | no |
| <a name="input_custom_arguments"></a> [custom\_arguments](#input\_custom\_arguments) | Additional CLI arguments for Traefik | `list(string)` | `[]` | no |
| <a name="input_custom_envs"></a> [custom\_envs](#input\_custom\_envs) | Custom environment variables | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_custom_image_registry"></a> [custom\_image\_registry](#input\_custom\_image\_registry) | Custom image registry | `string` | `""` | no |
| <a name="input_custom_image_repository"></a> [custom\_image\_repository](#input\_custom\_image\_repository) | Custom image repository | `string` | `""` | no |
| <a name="input_custom_image_tag"></a> [custom\_image\_tag](#input\_custom\_image\_tag) | Custom image tag | `string` | `""` | no |
| <a name="input_custom_plugins"></a> [custom\_plugins](#input\_custom\_plugins) | Additional Traefik plugins (proxmox discovery is a native first-party provider now, wired via var.proxmox\_provider — not a plugin) | <pre>map(object({<br/>    moduleName = string<br/>    version    = string<br/>  }))</pre> | `{}` | no |
| <a name="input_custom_ports"></a> [custom\_ports](#input\_custom\_ports) | Custom ports configuration. Typed `any` so it can carry a full Helm `ports.<name>` shape — e.g. a Hub multicluster uplink entrypoint { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } } — not just { port, protocol }. | `any` | `{}` | no |
| <a name="input_dashboard_entrypoints"></a> [dashboard\_entrypoints](#input\_dashboard\_entrypoints) | Dashboard entry points | `list(string)` | <pre>[<br/>  "traefik"<br/>]</pre> | no |
| <a name="input_dashboard_insecure"></a> [dashboard\_insecure](#input\_dashboard\_insecure) | Enable insecure dashboard access (no auth) | `bool` | `true` | no |
| <a name="input_dashboard_match_rule"></a> [dashboard\_match\_rule](#input\_dashboard\_match\_rule) | Match rule for the Traefik dashboard router | `string` | `""` | no |
| <a name="input_disk_interface"></a> [disk\_interface](#input\_disk\_interface) | Interface of the template's disk to resize (the standard cloud-image import recipe attaches it as scsi0) | `string` | `"scsi0"` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Disk size in GB. Must be at least the template's disk (Proxmox can't shrink on clone). | `number` | `20` | no |
| <a name="input_enable_access_logs"></a> [enable\_access\_logs](#input\_enable\_access\_logs) | Enable Traefik access logs | `bool` | `true` | no |
| <a name="input_enable_ai_gateway"></a> [enable\_ai\_gateway](#input\_enable\_ai\_gateway) | Enable Traefik Hub AI Gateway features | `bool` | `false` | no |
| <a name="input_enable_api_gateway"></a> [enable\_api\_gateway](#input\_enable\_api\_gateway) | Enable Traefik Hub API Gateway features | `bool` | `false` | no |
| <a name="input_enable_dashboard"></a> [enable\_dashboard](#input\_enable\_dashboard) | Enable Traefik dashboard | `bool` | `true` | no |
| <a name="input_enable_dashboard_discovery"></a> [enable\_dashboard\_discovery](#input\_enable\_dashboard\_discovery) | Self-register the Traefik VM via its own Notes labels (traefik.enable + dashboard router/service, as LINE-format `traefik.key=value` labels) so its OWN proxmox provider discovers the dashboard on @proxmox. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the VM isn't self-discovered at all. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container). NOT needed for proxmox discovery — that's a native first-party provider built into the Hub image — only for running a pre-release Hub build (e.g. the multicluster-uplink branch). | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the VM at cloud-init time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_labels"></a> [extra\_labels](#input\_extra\_labels) | Extra Traefik labels merged into the VM's own Notes/description (on top of the dashboard self-registration labels, when enabled), rendered as LINE-format `traefik.key=value` labels | `map(string)` | `{}` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB | `number` | `4096` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count | `number` | `2` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
| <a name="input_proxmox_provider"></a> [proxmox\_provider](#input\_proxmox\_provider) | Native first-party Hub Proxmox VE discovery provider — rendered as `--hub.providers.proxmox.*` (like ec2/azurevm/gce), NOT the old NX211 Yaegi plugin. No plugin download, so the VM needs no outbound internet to fetch a plugin. Proxmox has no ambient identity, so endpoint + token\_id are required when enabled — the token secret rides the separate sensitive var.proxmox\_api\_token. insecure\_skip\_verify defaults true (self-signed PVE certs are the lab norm). guest\_types is the KEY win over the plugin: it filters this gateway to one compute type (qemu OR lxc), so each child fronts only its own compute type instead of every child discovering every guest. | <pre>object({<br/>    enabled              = optional(bool, true)<br/>    endpoint             = optional(string, "")<br/>    token_id             = optional(string, "")<br/>    refresh_seconds      = optional(number, 30)<br/>    insecure_skip_verify = optional(bool, true)<br/>    guest_types          = optional(list(string), []) # ["qemu"] or ["lxc"]; empty discovers both<br/>    exposed_by_default   = optional(bool, false)<br/>    ip_mode              = optional(string, "private")<br/>    nodes                = optional(list(string), [])<br/>    tag_filter           = optional(string, "")<br/>  })</pre> | `{}` | no |
| <a name="input_snippet_datastore_id"></a> [snippet\_datastore\_id](#input\_snippet\_datastore\_id) | Datastore the cloud-init user-data snippet is uploaded to (Snippets content type must be enabled; uploads ride the bpg provider's SSH access) | `string` | `"local"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt. | `string` | `""` | no |
| <a name="input_template_name"></a> [template\_name](#input\_template\_name) | Name of the template to clone (resolved to a VMID on the node). Takes precedence over template\_vm\_id. | `string` | `""` | no |
| <a name="input_template_vm_id"></a> [template\_vm\_id](#input\_template\_vm\_id) | VMID of the template to clone. Provide this OR template\_name. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template with qemu-guest-agent (the agent reports the guest IP the parent dials). | `number` | `0` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the Traefik VM | `string` | `"traefik"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1). private\_ip and public\_ip are the SAME guest address — Proxmox guests have one primary IP and no cloud public-IP concept. |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their guest IP addresses (the parent dials https://<ip>:9443) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their guest IP addresses — identical to private\_ips (no public-IP concept on Proxmox; kept for sibling-parity) |
<!-- END_TF_DOCS -->