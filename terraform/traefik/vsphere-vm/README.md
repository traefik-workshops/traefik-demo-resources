# traefik/vsphere-vm

Traefik Hub on a **vSphere VM** — the on-prem sibling of `traefik/ec2` / `traefik/azure-vm` / `traefik/oci-vm`. Clones a user-provided **cloud-init-enabled Ubuntu cloud-image template**, extracts its Traefik configuration from `traefik/shared` (via Helm template) and boots it with the shared `traefik/cloud-init` template — as a systemd binary, or as a docker container when `enable_preview_mode = true` (required while the `vsphere` provider isn't in a tagged Hub release).

## The vsphere provider

`var.vsphere_provider` renders `--hub.providers.vsphere.*` CLI flags. The gateway discovers workload VMs by their **`guestinfo.traefik` extraConfig entry** — a JSON object of dotted Traefik labels (see `apps/whoami/vsphere`); `constraints` match those labels plus a synthesized `name` pseudo-label. There is **no port discovery** (vSphere has no per-VM firewall primitive), so workloads must set the `server.port` label. `ipMode` `private` and `public` both resolve to a VM's primary guest IP (reported by open-vm-tools); `ipv6` picks the global IPv6 address.

**Credentials are explicit** — vSphere has no ambient identity (no instance profile / managed identity), so the provider takes `endpoint` + `username` (in the object) and `var.vsphere_password` (sensitive). Point them at a **read-only vCenter role**; the password lands in the VM's systemd unit / container args, which is demo-grade — don't reuse an admin credential.

Routerless discovery (`default_rule = "{{/*routerless*/}}"`) works exactly like the EC2/Azure/OCI siblings: VMs land as services only, and routers come from file-provider rules.

## Example usage

```hcl
module "traefik_vsphere" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/vsphere-vm?ref=v6.1.4"

  datacenter = "dc-01"
  datastore  = "datastore-01"
  cluster    = "cluster-01"
  network    = "VM Network"
  template   = "ubuntu-24.04-cloudimg"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  vsphere_provider = {
    endpoint   = "vcenter.lab.example.com"
    username   = "traefik-ro@vsphere.local"
    datacenter = "dc-01"
  }
  vsphere_password = var.vsphere_password

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

- vCenter credentials for terraform (clone rights) **plus** the read-only provider credential above — they can differ.
- A **cloud-init-enabled Ubuntu cloud-image template** (see `compute/vsphere/k3s`'s README); DHCP on the network; `helm` on the machine running terraform (config extraction via `helm template`).

## Notes

- `enable_dashboard_discovery` (default on) self-registers the VM's dashboard through its own `guestinfo.traefik` entry (`dashboard@vsphere`); disable it when a file-rule uplink advertises the dashboard instead.
- Outputs mirror the VM siblings (`instances` / `private_ips` / `public_ips`) so demo code reads identically — on vSphere both IP maps carry the same guest address.

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
| <a name="input_datacenter"></a> [datacenter](#input\_datacenter) | Name of the vSphere datacenter the VM is created in | `string` | n/a | yes |
| <a name="input_datastore"></a> [datastore](#input\_datastore) | Name of the datastore backing the VM's disk | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Name of the port group / network the VM's NIC joins (DHCP is assumed; the parent dials the VM's guest IP :9443 in-network) | `string` | n/a | yes |
| <a name="input_template"></a> [template](#input\_template) | Name of the VM template to clone. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (e.g. imported from ubuntu-24.04-server-cloudimg-amd64.ova) — a plain installer-built template ignores the guestinfo userdata and Traefik never starts. | `string` | n/a | yes |
| <a name="input_cluster"></a> [cluster](#input\_cluster) | Name of the compute cluster to place the VM in (its root resource pool). Provide this OR resource\_pool. | `string` | `""` | no |
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
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Disk size in GB. Grown to at least the template's disk (vSphere can't shrink on clone). | `number` | `20` | no |
| <a name="input_enable_access_logs"></a> [enable\_access\_logs](#input\_enable\_access\_logs) | Enable Traefik access logs | `bool` | `true` | no |
| <a name="input_enable_ai_gateway"></a> [enable\_ai\_gateway](#input\_enable\_ai\_gateway) | Enable Traefik Hub AI Gateway features | `bool` | `false` | no |
| <a name="input_enable_api_gateway"></a> [enable\_api\_gateway](#input\_enable\_api\_gateway) | Enable Traefik Hub API Gateway features | `bool` | `false` | no |
| <a name="input_enable_dashboard"></a> [enable\_dashboard](#input\_enable\_dashboard) | Enable Traefik dashboard | `bool` | `true` | no |
| <a name="input_enable_dashboard_discovery"></a> [enable\_dashboard\_discovery](#input\_enable\_dashboard\_discovery) | Self-register the Traefik VM via its own `guestinfo.traefik` entry (traefik.enable + dashboard router/service) so its OWN vsphere provider discovers the dashboard as dashboard@vsphere. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the VM isn't self-discovered at all. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. vsphere) | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the VM at cloud-init time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_labels"></a> [extra\_labels](#input\_extra\_labels) | Extra Traefik labels merged into the VM's own `guestinfo.traefik` extraConfig entry (on top of the dashboard self-registration labels, when enabled) | `map(string)` | `{}` | no |
| <a name="input_extra_runcmd"></a> [extra\_runcmd](#input\_extra\_runcmd) | Extra shell blocks appended to cloud-init runcmd, after Docker is installed and before traefik-hub starts. Used to run workload containers on the gateway VM itself (the docker-provider leg). | `list(string)` | `[]` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_folder"></a> [folder](#input\_folder) | VM folder to place the VM in. Empty = the datacenter root. | `string` | `""` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB | `number` | `4096` | no |
| <a name="input_mount_docker_socket"></a> [mount\_docker\_socket](#input\_mount\_docker\_socket) | Bind /var/run/docker.sock into the preview-mode Traefik container so its docker provider can reach the local daemon. Root-equivalent access to the host, so leave it off for any gateway that is not the docker-provider leg. | `bool` | `false` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count | `number` | `2` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
| <a name="input_resource_pool"></a> [resource\_pool](#input\_resource\_pool) | Name/path of the resource pool to place the VM in. Takes precedence over cluster. | `string` | `""` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt. | `string` | `""` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the Traefik VM | `string` | `"traefik"` | no |
| <a name="input_vsphere_password"></a> [vsphere\_password](#input\_vsphere\_password) | vCenter password the gateway's vsphere provider authenticates with. Point it at a READ-ONLY vCenter role — discovery only lists VMs. Optional, because a child on vSphere need not discover BY vSphere: the docker-provider leg runs the same module with vsphere\_provider.enabled = false and has no business carrying a vCenter secret. | `string` | `""` | no |
| <a name="input_vsphere_provider"></a> [vsphere\_provider](#input\_vsphere\_provider) | Traefik Hub vsphere provider configuration (hub.providers.vsphere). The provider is<br/>vCENTER-NATIVE: it reads service membership from vCenter TAGS and takes its routing<br/>intent from a base configuration, rather than from per-VM labels.<br/><br/>  service\_name\_category\_key  the vCenter tag CATEGORY whose tags name services. A VM<br/>                             tagged `vmrr` in that category is a server of the `vmrr`<br/>                             service; with a MULTIPLE-cardinality category a VM can<br/>                             carry several tags and back several services (that is how<br/>                             one fleet is published under three LB strategies).<br/>  config\_endpoint            URL the gateway polls for the base config (GitOps), OR<br/>  filename                   a path to it on the gateway host. Exactly one.<br/><br/>Discovery goes through vCenter's vAPI tagging service, which a standalone ESXi host<br/>does not serve — so this provider requires vCenter, by design.<br/><br/>vSphere has no ambient identity, so endpoint + username are required when enabled; the<br/>password rides the separate sensitive var.vsphere\_password. endpoint may be a bare<br/>vCenter host (the provider applies https + /sdk); insecure\_skip\_verify defaults on<br/>(self-signed vCenter certs are the norm); datacenter empty = all datacenters. | <pre>object({<br/>    enabled                     = optional(bool, true)<br/>    endpoint                    = optional(string, "")<br/>    username                    = optional(string, "")<br/>    insecure_skip_verify        = optional(bool, true)<br/>    datacenter                  = optional(string, "")<br/>    ip_mode                     = optional(string, "private")<br/>    service_name_category_key   = optional(string, "TraefikServiceName")<br/>    config_endpoint             = optional(string, "")<br/>    config_insecure_skip_verify = optional(bool, false)<br/>    filename                    = optional(string, "")<br/>    refresh_seconds             = optional(number, null)<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1). private\_ip and public\_ip are the SAME guest address — vSphere VMs have one primary IP and no cloud public-IP concept (the provider's private/public ipModes both resolve to it). |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their guest IP addresses (the parent dials https://<ip>:9443) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their guest IP addresses — identical to private\_ips (no public-IP concept on vSphere; kept for sibling-parity) |
<!-- END_TF_DOCS -->