# traefik/vmservice

Traefik Hub on a **vSphere VM Service VM** — the child gateway of `traefik/vsphere-vm`, on a VM that terraform did **not** clone. The module hands the **vSphere Supervisor's VM Service** (vm-operator) a `VirtualMachine` object inside a vSphere Namespace; the Supervisor builds the VM from a content-library image, a `VirtualMachineClass`, and the namespace's storage class and network, and boots it with the shared `traefik/cloud-init` user-data delivered as a `rawCloudConfig` bootstrap Secret. Configuration is extracted from `traefik/shared` (via Helm template) exactly as on every VM sibling; the gateway runs as a systemd binary, or as a docker container when `enable_preview_mode = true` (required while the `vsphere` provider isn't in a tagged Hub release).

## The vsphere provider

Identical to `traefik/vsphere-vm` — this is the same gateway on a differently-provisioned machine. `var.vsphere_provider` renders `--hub.providers.vsphere.*`: discovery by vCenter **tags** in `service_name_category_key`, routing intent from `config_endpoint` (GitOps) or `filename`, explicit vCenter credentials (`var.vsphere_password`), `ipMode` resolving to the guest address VMware Tools reports. A VM Service VM is an ordinary vCenter VM, so the provider running *on* it discovers clone-provisioned and VM-Service-provisioned workloads alike; give each child its own tag category when two children share a vCenter.

## What is different from the clone sibling

- **No placement inputs** (`datacenter`, `datastore`, `cluster`/`resource_pool`, `network`, `template`, `folder`, `num_cpus`, `memory`, `disk_size`). Instead: `namespace`, `class_name` (the VM class sizes the VM), `image_name`, `storage_class`, optional `network_name`.
- **The address is known only after apply** — vm-operator assigns it from the namespace network and the module reads `status.network.primaryIP4` back (`private_ips`). A parent that dials this child's `:9443` uplink cannot take the address from this module at plan time: feed it through a variable filled between two applies.
- **No `guestinfo.traefik` self-registration** (`enable_dashboard_discovery` / `extra_labels` do not exist here): VM Service exposes no extraConfig, and the tag-based provider never read it anyway — advertise the dashboard over a file-rule uplink.
- Needs `kubectl` (the Supervisor kubeconfig) and `jq` on the machine running terraform, for the address wait; `helm` for the config extraction, as every sibling.

## Example usage

```hcl
module "traefik_vmsvc" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/vmservice?ref=v6.4.0"

  providers = { kubectl = kubectl.supervisor }

  namespace     = "traefik-ns"
  class_name    = "best-effort-small"
  image_name    = "ubuntu-24.04-cloudimg"
  storage_class = "wcp-storage"
  vm_name       = "traefik-vmsvc"

  kubeconfig         = "/path/to/supervisor-kubeconfig.yaml"
  kubeconfig_context = "my-supervisor-ctx"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true
  enable_preview_mode = true # the vsphere provider build runs as a container

  vsphere_provider = {
    endpoint                  = "vcenter.lab.example.com"
    username                  = "traefik-ro@vsphere.local"
    datacenter                = "dc-01"
    service_name_category_key = "TraefikServiceNameVMSvc"
    config_endpoint           = "https://git.example.com/config/vmsvc/dynamic.yaml"
  }
  vsphere_password = var.vsphere_password

  # Join a Hub mesh: uplink entrypoint on :9443; the parent dials this VM's guest IP,
  # read from `private_ips` AFTER apply.
  multicluster_provider = { enabled = true }
  custom_ports = {
    vmsvcuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }
}
```

## Prerequisites

- A vSphere Namespace with a `VirtualMachineClass`, a storage class and a content library holding a **cloud-init-enabled Ubuntu cloud image**.
- A Supervisor kubeconfig for the `kubectl` provider and the wait script.
- vCenter credentials for the provider (read-only; discovery only lists VMs and reads tags).

## Notes

- Outputs mirror the VM siblings (`instances` / `private_ips` / `public_ips`) so demo code reads identically — on vSphere both IP maps carry the same guest address.
- `api_version` defaults to `v1alpha3`; a Supervisor serves several versions of `vmoperator.vmware.com`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.14 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_external"></a> [external](#provider\_external) | >= 2.0 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | >= 1.14 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_config"></a> [config](#module\_config) | ../shared | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [kubectl_manifest.bootstrap](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.vm](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [external_external.guest](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_class_name"></a> [class\_name](#input\_class\_name) | VirtualMachineClass the gateway is sized by (e.g. best-effort-small). `kubectl get virtualmachineclass -n <namespace>` lists the ones bound to the namespace. | `string` | n/a | yes |
| <a name="input_image_name"></a> [image\_name](#input\_image\_name) | VirtualMachineImage the gateway boots from — the name `kubectl get vmi -n <namespace>` shows. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE (ubuntu-*-server-cloudimg-amd64.ova) for the rawCloudConfig bootstrap to take. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | vSphere Namespace (a Supervisor namespace) the gateway VirtualMachine is created in. The VirtualMachineClass, the storage class and the image must all be associated with it. | `string` | n/a | yes |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Storage class for the gateway's disk (the namespace's storage policy, e.g. wcp-storage). | `string` | n/a | yes |
| <a name="input_api_version"></a> [api\_version](#input\_api\_version) | vmoperator.vmware.com API version to write the VirtualMachine with. A Supervisor serves several (`kubectl api-resources | grep vmoperator`); v1alpha3 carries the rawCloudConfig bootstrap this module uses and is served by vSphere 8U2+ and 9. | `string` | `"v1alpha3"` | no |
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
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. vsphere) | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the VM at cloud-init time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_runcmd"></a> [extra\_runcmd](#input\_extra\_runcmd) | Extra shell blocks appended to cloud-init runcmd, after Docker is installed and before traefik-hub starts. Used to run workload containers on the gateway VM itself (the docker-provider leg). | `list(string)` | `[]` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_ip_wait_timeout"></a> [ip\_wait\_timeout](#input\_ip\_wait\_timeout) | Seconds to wait for the gateway's status.network.primaryIP4 before failing the apply. vm-operator powers the VM on and the namespace network assigns the address within a minute or two on a healthy Supervisor. | `number` | `600` | no |
| <a name="input_kubeconfig"></a> [kubeconfig](#input\_kubeconfig) | Path to the kubeconfig the guest-address wait (local-exec kubectl) should use — the SUPERVISOR kubeconfig, the same one the kubectl provider that creates the VirtualMachine is configured with. Empty = kubectl's ambient config. | `string` | `""` | no |
| <a name="input_kubeconfig_context"></a> [kubeconfig\_context](#input\_kubeconfig\_context) | Context inside `kubeconfig` to use. Set it so the wait targets a named context instead of whatever the machine-global current-context happens to be at that instant. | `string` | `""` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_mount_docker_socket"></a> [mount\_docker\_socket](#input\_mount\_docker\_socket) | Bind /var/run/docker.sock into the preview-mode Traefik container so its docker provider can reach the local daemon. Root-equivalent access to the host, so leave it off for any gateway that is not the docker-provider leg. | `bool` | `false` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Network the gateway's single interface joins (an NSX segment or VDS port group the namespace is entitled to). Empty = the namespace's default network. The parent dials the VM's guest IP :9443 on it. | `string` | `""` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
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
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik VM with its details (keyed like traefik/vsphere-vm: <vm\_name>-1). private\_ip is status.network.primaryIP4 — the guest address the namespace network assigned, known only after apply. |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their guest IP addresses (the parent dials https://<ip>:9443). Known only after apply — feed a parent that needs it at plan time through a variable filled between two applies. |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their guest IP addresses — identical to private\_ips (no public-IP concept on vSphere; kept for sibling-parity) |
<!-- END_TF_DOCS -->
