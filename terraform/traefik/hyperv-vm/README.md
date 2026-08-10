# traefik/hyperv-vm

The **multicluster CHILD on Hyper-V/SCVMM** — the Hyper-V sibling of `traefik/ec2` / `traefik/vsphere-vm` / `traefik/proxmox-vm`. One VM off the golden Ubuntu cloud-image parent (differencing VHDX + NoCloud seed, via `compute/hyperv/vm`) runs the Hub image with config extracted from `traefik/shared`, and guest discovery is the **native first-party Hub Hyper-V provider** delivered as static-config CLI flags (`--hub.providers.hyperv.*`).

**The provider talks to SCVMM, not to Hyper-V hosts.** Standalone Hyper-V has no API and no tags; SCVMM is the estate plane. Discovery is one PowerShell round trip per poll over **WinRM HTTPS to the VMM management server** (`Get-SCVirtualMachine`), reading line-format `traefik.*` labels from each VM's **VMM Description** and addresses from VMM's adapter view (VMM host agent + guest KVP daemon; the `traefik.hyperv.ip` label is the escape hatch for KVP-less guests). Hyper-V hosts need **no** WinRM exposure to the gateway.

**Scoping — the enterprise delegation story**: `cloud` (a VMM Cloud, the quota/delegation boundary) or `host_group` (a `VMHostGroup` path) scope one gateway to one estate slice; they are mutually exclusive, and both empty discovers the whole estate.

**Credentials**: WinRM has no ambient identity, so `hyperv_provider.username` + `hyperv_password` are an explicit account — a member of VMM's **Read-Only Administrator** user role that can also open raw WinRS shells on the VMM server (non-Administrators need the `A;;GXGR` ACE in `WSMan:\localhost\Service\RootSDDL` there; `Remote Management Users` alone is **not** sufficient).

**Static addressing**: `ip_address` is an input, so the hub's `children` uplink map is plan-known — single-pass, no PENDING. **No dashboard self-registration** (unlike proxmox): self-labels would need a VMM-side write credential this module deliberately does not carry — advertise the dashboard over a file-rule uplink instead.

## Example usage

```hcl
module "vm_traefik" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/hyperv-vm?ref=v6.1.0"

  vm_name          = "traefik-vm"
  host_winrm       = { host = "203.0.113.10", username = "Admin", password = var.host_admin_password }
  parent_vhdx_path = "C:\\traefik-lab\\golden\\noble-golden.vhdx"
  ip_address       = "10.99.0.20/24"
  gateway          = "10.99.0.1"
  dns_servers      = ["10.99.0.2"]

  traefik_hub_token = var.traefik_hub_token

  hyperv_provider = {
    vmm_server = "10.99.0.6"                # the SCVMM management server
    username   = "LAB\\traefik-discovery"   # Read-Only Administrator + RootSDDL ACE
  }
  hyperv_password = var.discovery_password

  multicluster_provider = { enabled = true }
  custom_ports = {
    vmuplink = { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } }
  }
}
```

## Prerequisites

- Everything `compute/hyperv/vm` needs (host WinRM HTTPS, golden parent VHDX, the virtual switch).
- An SCVMM management server on WinRM HTTPS `:5986` (NTLM, self-signed ok with the default `insecure_skip_verify`), a healthy VMM host agent (populates the adapter view the provider reads), and the read-only discovery account described above.
- `helm` on the operator machine (`traefik/shared` extracts the CLI args via `helm template`).
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4 |

## Providers

No providers.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Default gateway for the VM — the Hyper-V internal NAT switch's host-side address (e.g. 10.99.0.1). | `string` | n/a | yes |
| <a name="input_host_winrm"></a> [host\_winrm](#input\_host\_winrm) | WinRM HTTPS access to the Hyper-V HOST the gateway VM is created on (see compute/hyperv/vm). Creation plane only — the DISCOVERY credential (var.hyperv\_provider + var.hyperv\_password) targets the SCVMM server, a different machine and a different account. | <pre>object({<br/>    host     = string<br/>    port     = optional(number, 5986)<br/>    username = string<br/>    password = string<br/>    https    = optional(bool, true)<br/>    insecure = optional(bool, true)<br/>    use_ntlm = optional(bool, true)<br/>    timeout  = optional(string, "10m")<br/>  })</pre> | n/a | yes |
| <a name="input_ip_address"></a> [ip\_address](#input\_ip\_address) | Static CIDR the gateway takes via its NoCloud network-config (e.g. 10.99.0.20/24). PLAN-KNOWN by design: the hub's multicluster `children` map dials https://<this>:9443, so a single apply wires the uplink — no PENDING second pass. | `string` | n/a | yes |
| <a name="input_parent_vhdx_path"></a> [parent\_vhdx\_path](#input\_parent\_vhdx\_path) | Golden parent VHDX the differencing disk chains to — a generic Ubuntu CLOUD IMAGE conversion (never -azure.vhd) with linux-cloud-tools baked in (see compute/hyperv/vm). | `string` | n/a | yes |
| <a name="input_custom_arguments"></a> [custom\_arguments](#input\_custom\_arguments) | Additional CLI arguments for Traefik | `list(string)` | `[]` | no |
| <a name="input_custom_envs"></a> [custom\_envs](#input\_custom\_envs) | Custom environment variables | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_custom_image_registry"></a> [custom\_image\_registry](#input\_custom\_image\_registry) | Custom image registry | `string` | `""` | no |
| <a name="input_custom_image_repository"></a> [custom\_image\_repository](#input\_custom\_image\_repository) | Custom image repository | `string` | `""` | no |
| <a name="input_custom_image_tag"></a> [custom\_image\_tag](#input\_custom\_image\_tag) | Custom image tag | `string` | `""` | no |
| <a name="input_custom_plugins"></a> [custom\_plugins](#input\_custom\_plugins) | Additional Traefik plugins (hyperv discovery is a native first-party provider, wired via var.hyperv\_provider — not a plugin) | <pre>map(object({<br/>    moduleName = string<br/>    version    = string<br/>  }))</pre> | `{}` | no |
| <a name="input_custom_ports"></a> [custom\_ports](#input\_custom\_ports) | Custom ports configuration. Typed `any` so it can carry a full Helm `ports.<name>` shape — e.g. a Hub multicluster uplink entrypoint { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } } — not just { port, protocol }. | `any` | `{}` | no |
| <a name="input_dashboard_entrypoints"></a> [dashboard\_entrypoints](#input\_dashboard\_entrypoints) | Dashboard entry points | `list(string)` | <pre>[<br/>  "traefik"<br/>]</pre> | no |
| <a name="input_dashboard_insecure"></a> [dashboard\_insecure](#input\_dashboard\_insecure) | Enable insecure dashboard access (no auth) | `bool` | `true` | no |
| <a name="input_dashboard_match_rule"></a> [dashboard\_match\_rule](#input\_dashboard\_match\_rule) | Match rule for the Traefik dashboard router | `string` | `""` | no |
| <a name="input_dns_servers"></a> [dns\_servers](#input\_dns\_servers) | DNS servers for the VM (the lab router's dnsmasq on the hyperv demo). Static guests get no DHCP: without this the gateway can resolve neither its image registry nor collector.<domain>, and its cloud-init self-gate stalls. | `list(string)` | `[]` | no |
| <a name="input_enable_access_logs"></a> [enable\_access\_logs](#input\_enable\_access\_logs) | Enable Traefik access logs | `bool` | `true` | no |
| <a name="input_enable_ai_gateway"></a> [enable\_ai\_gateway](#input\_enable\_ai\_gateway) | Enable Traefik Hub AI Gateway features | `bool` | `false` | no |
| <a name="input_enable_api_gateway"></a> [enable\_api\_gateway](#input\_enable\_api\_gateway) | Enable Traefik Hub API Gateway features | `bool` | `false` | no |
| <a name="input_enable_dashboard"></a> [enable\_dashboard](#input\_enable\_dashboard) | Enable Traefik dashboard | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container). Needed while the hyperv provider ships only in the demo-hyperv build (a mutable pre-release tag the cloud-init re-pulls on every start) — not for anything about Hyper-V itself. | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the VM at cloud-init time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_runcmd"></a> [extra\_runcmd](#input\_extra\_runcmd) | Extra shell blocks appended to cloud-init runcmd, after Docker is installed and before traefik-hub starts. Used to run workload containers on the gateway VM itself (the docker-provider leg). | `list(string)` | `[]` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_hyperv_password"></a> [hyperv\_password](#input\_hyperv\_password) | Password of the WinRM account the native hyperv provider discovers with (pairs with hyperv\_provider.username → --hub.providers.hyperv.password). Point it at the READ-ONLY discovery account, not a VMM administrator. | `string` | `""` | no |
| <a name="input_hyperv_provider"></a> [hyperv\_provider](#input\_hyperv\_provider) | Native first-party Hub Hyper-V discovery provider — rendered as `--hub.providers.hyperv.*` (like ec2/azurevm/gce/proxmox). SCVMM-BASED: vmm\_server is the SCVMM MANAGEMENT server (never a Hyper-V host — standalone hosts have no API and are not dialed), reached over WinRM HTTPS (NTLM; insecure\_skip\_verify defaults true for the lab's self-signed listener). username must be domain-qualified (e.g. LAB\\traefik-discovery), a member of VMM's Read-Only Administrator user role that can open raw WinRS shells on the VMM server (non-admins need the A;;GXGR RootSDDL ACE — Remote Management Users alone is NOT sufficient); the password rides the separate sensitive var.hyperv\_password. `cloud` (a VMM Cloud name) and `host_group` (a VMHostGroup path like "All Hosts\\Production") each scope one gateway to one estate slice — the enterprise delegation story — and are MUTUALLY EXCLUSIVE; both empty discovers the whole estate. ip\_mode private/public both resolve to the VMM-reported guest address on-prem; `label` reads traefik.hyperv.ip — the per-VM escape hatch for KVP-less guests. | <pre>object({<br/>    enabled              = optional(bool, true)<br/>    vmm_server           = optional(string, "")<br/>    port                 = optional(number, 5986)<br/>    username             = optional(string, "")<br/>    refresh_seconds      = optional(number, 30)<br/>    insecure_skip_verify = optional(bool, true)<br/>    cloud                = optional(string, "")<br/>    host_group           = optional(string, "")<br/>    constraints          = optional(string, "")<br/>    default_rule         = optional(string, "")<br/>    exposed_by_default   = optional(bool, false)<br/>    ip_mode              = optional(string, "private")<br/>  })</pre> | `{}` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB (static memory — the compute module disables dynamic memory) | `number` | `4096` | no |
| <a name="input_mount_docker_socket"></a> [mount\_docker\_socket](#input\_mount\_docker\_socket) | Bind /var/run/docker.sock into the preview-mode Traefik container so its docker provider can reach the local daemon. Root-equivalent access to the host, so leave it off for any gateway that is not the docker-provider leg. | `bool` | `false` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count | `number` | `2` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt. | `string` | `""` | no |
| <a name="input_switch_name"></a> [switch\_name](#input\_switch\_name) | Hyper-V virtual switch the VM's NIC joins (the parent dials this VM's static IP :9443 in-network). | `string` | `"traefik-lab"` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the Traefik VM (instance key becomes <vm\_name>-1, the traefik/ec2 scheme) | `string` | `"traefik"` | no |
| <a name="input_workdir"></a> [workdir](#input\_workdir) | Host directory the VM's seed + differencing disk live under. | `string` | `"C:\\traefik-lab"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik VM with its details (keyed like traefik/ec2: <vm\_name>-1). private\_ip and public\_ip are the SAME statically-planned guest address — Hyper-V guests have one primary IP and no cloud public-IP concept. |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their static guest IP addresses (the parent dials https://<ip>:9443). PLAN-KNOWN — the hub's children map wires in one pass, no PENDING. |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their guest IP addresses — identical to private\_ips (no public-IP concept on Hyper-V; kept for sibling-parity) |
| <a name="output_uplink_address"></a> [uplink\_address](#output\_uplink\_address) | The https://<static-ip>:9443 address the hub's multicluster children map dials — plan-known, because the address is an input. |
<!-- END_TF_DOCS -->
