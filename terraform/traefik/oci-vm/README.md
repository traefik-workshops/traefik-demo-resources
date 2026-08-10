# traefik/oci-vm

Traefik Hub on one OCI Compute VM — the OCI sibling of `traefik/ec2`/`traefik/azure-vm`/`traefik/gce` and a **multicluster CHILD**: it joins a Hub parent over a `:9443` uplink and discovers local whoami VMs via its own `hub.providers.oci` provider.

Composes `traefik/shared` (extracted Helm config) and `traefik/cloud-init` exactly like `traefik/ec2`. The oci provider ships only in a preview image (`ghcr.io/zalbiraw/traefik-hub`), so the demo sets `enable_preview_mode = true` + `custom_image_*` and the VM runs the image as a docker container (`--network host`, so IMDS and the uplink work).

Auth is **instance principals** — no API keys on the VM. `enable_instance_principal` (default on) instantiates `security/oci-instance-principal`: a dynamic group matching every instance in the compartment plus a policy, so the SDK's IMDS flow (`useInstancePrincipal=true`) just works. The module appends the provider flags (`--hub.providers.oci.compartmentID/ipMode/exposedByDefault/useInstancePrincipal/...`) to `custom_arguments`; `compartment_id` defaults to the module's own.

**Workload config note:** the oci provider reads Traefik labels from **freeform tags** with dotted keys (`traefik.enable`, `traefik.http.services.<n>.loadbalancer.server.port`, ...) — exactly like EC2/Azure tags. `enable_dashboard_discovery` self-registers the dashboard that way. Per-instance IP-mode override: the `traefik.oci.ipmode` tag.

## Example usage

```hcl
module "oci_traefik" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/oci-vm?ref=v6.0.0"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  compartment_id = var.compartment_id
  subnet_id      = module.oke.nodes_subnet_id

  # The oci provider isn't in a Hub release — run the custom image as a container.
  enable_preview_mode     = true
  custom_image_registry   = "docker.io"
  custom_image_repository = "zalbiraw/traefik-hub"
  custom_image_tag        = "latest"

  # Hub uplink entrypoint on :9443 (TLS; the parent verifies with insecureSkipVerify).
  multicluster_provider = { enabled = true }
  custom_ports = {
    ociuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }

  # Advertise the provider-discovered service over the uplink (same shape as traefik/ec2).
  file_provider_config = yamlencode({
    http = {
      uplinks = { oci-whoami = { entryPoints = ["ociuplink"] } }
      routers = {
        oci-whoami = {
          rule    = "PathPrefix(`/`)"
          service = "whoami@oci"
          uplinks = ["oci-whoami"]
        }
      }
    }
  })
}
```

## Prerequisites

- OCI credentials with Compute/Network permissions **and IAM rights** (dynamic group + policy) in the tenancy — or set `enable_instance_principal = false` and create `security/oci-instance-principal` yourself (its resource names are fixed, so it can only exist once per tenancy).
- A joinable subnet; `:9443` must be reachable in-VCN. `compute/oracle/oke`'s subnets already allow all intra-VCN traffic; for other VCNs, `enable_nsg` (+ `vcn_id`) creates an NSG opening 80/443/8080/9443 — the OCI analog of `compute/azure/vnet`'s `extra_ingress_ports = [9443]` / `traefik/gce`'s `enable_firewall`.
- `helm` on the machine running terraform (`traefik/shared` extracts config via `helm template`).

## Notes

- One VM (no replica set) — the parent dials `values(module.oci_traefik.private_ips)[0]` on `:9443`.
- `enable_dashboard_discovery = false` when the dashboard is advertised via a file-rule uplink (same cleanup as the EC2/Azure spokes).
- Boot image defaults to the latest Canonical Ubuntu 24.04 platform image (the cloud-init installs docker via apt).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_oci"></a> [oci](#provider\_oci) | ~> 7.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [oci_core_network_security_group.traefik](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group) | resource |
| [oci_core_network_security_group_security_rule.ingress](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group_security_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | OCID of the compartment the VM is created in (also the oci provider's default discovery scope and the instance-principal dynamic group's match) | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | OCID of the existing subnet the VM VNIC joins (the parent dials the VM's private IP :9443 in-VCN, e.g. compute/oracle/oke's nodes\_subnet\_id) | `string` | n/a | yes |
| <a name="input_availability_domain"></a> [availability\_domain](#input\_availability\_domain) | Availability domain the VM is placed in. Empty = the compartment's first AD (same pick as compute/oracle/oke). | `string` | `""` | no |
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
| <a name="input_enable_dashboard_discovery"></a> [enable\_dashboard\_discovery](#input\_enable\_dashboard\_discovery) | Self-register the Traefik VM via freeform tags (traefik.enable + dashboard router/service) so its OWN oci provider discovers the dashboard as dashboard@oci. Disable when the dashboard is advertised another way (e.g. a file-rule uplink) so the VM isn't self-discovered at all. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Enable Traefik debug mode (pprof) | `bool` | `false` | no |
| <a name="input_enable_instance_principal"></a> [enable\_instance\_principal](#input\_enable\_instance\_principal) | Instantiate security/oci-instance-principal (dynamic group matching the compartment's instances + policy) — the oci provider's keyless credential. Requires IAM rights; disable when the demo already created it (the dynamic group/policy names are fixed). | `bool` | `true` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_nsg"></a> [enable\_nsg](#input\_enable\_nsg) | Create an NSG opening nsg\_ingress\_ports to the VM from nsg\_source\_cidr (mirrors traefik/gce's enable\_firewall). Off by default — compute/oracle/oke's security list already allows all intra-VCN traffic. Requires vcn\_id. | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. oci) | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Assign a public IP to the VM (requires a public subnet). Off by default — the parent dials the private IP (same VCN). | `bool` | `false` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the VM at cloud-init time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra freeform tags to apply to the VM | `map(string)` | `{}` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_home_region"></a> [home\_region](#input\_home\_region) | Tenancy home region identifier (e.g. us-ashburn-1). OCI IAM writes only succeed against the home region, so the instance-principal dynamic group + policy are created there via the OCI CLI. Required when enable\_instance\_principal = true. | `string` | `""` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_memory_in_gbs"></a> [memory\_in\_gbs](#input\_memory\_in\_gbs) | Memory (GB) for the VM | `number` | `4` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_nsg_ids"></a> [nsg\_ids](#input\_nsg\_ids) | Existing network security group OCIDs to attach to the VM VNIC (on top of the optional module-created NSG) | `list(string)` | `[]` | no |
| <a name="input_nsg_ingress_ports"></a> [nsg\_ingress\_ports](#input\_nsg\_ingress\_ports) | TCP ports the module-created NSG opens on the VM. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials. | `list(number)` | <pre>[<br/>  80,<br/>  443,<br/>  8080,<br/>  9443<br/>]</pre> | no |
| <a name="input_nsg_source_cidr"></a> [nsg\_source\_cidr](#input\_nsg\_source\_cidr) | Source CIDR the module-created NSG allows. Default covers RFC1918 VCNs (compute/oracle/oke's VCN is 10.0.0.0/16). | `string` | `"10.0.0.0/8"` | no |
| <a name="input_oci_provider"></a> [oci\_provider](#input\_oci\_provider) | Traefik Hub oci provider configuration (hub.providers.oci). compartment\_id defaults to the module's compartment\_id; region defaults to the instance's own (from IMDS). No configFilePath/profile: useInstancePrincipal resolves the VM's identity keylessly (see enable\_instance\_principal). The base configuration (the services — with port/strategy/health checks — that discovered IPs merge into, plus any routers/uplinks) comes from config\_endpoint (a GitOps URL the provider polls, e.g. the hub's git-config-server) OR filename (a path baked onto the gateway — forces VM replacement on every config change, offline use only). At most one. | <pre>object({<br/>    enabled                = optional(bool, true)<br/>    compartment_id         = optional(string, "")<br/>    region                 = optional(string, "")<br/>    use_instance_principal = optional(bool, true)<br/>    ip_mode                = optional(string, "private")<br/>    # GitOps URL the provider polls for the base config — the mechanism that<br/>    # makes a routing-intent change a config push, not a VM replacement.<br/>    config_endpoint             = optional(string, "")<br/>    config_insecure_skip_verify = optional(bool, false)<br/>    # Offline alternative: a base-config file on the gateway (deliver it via<br/>    # extra_files to a mounted path, e.g. /data/oci-base.yaml). Mutually<br/>    # exclusive with config_endpoint.<br/>    filename             = optional(string, "")<br/>    service_name_tag_key = optional(string, "TraefikServiceName")<br/>    refresh_seconds      = optional(number, null)<br/>  })</pre> | `{}` | no |
| <a name="input_ocpus"></a> [ocpus](#input\_ocpus) | OCPUs for the VM (1 OCPU = 2 vCPUs on E4.Flex) | `number` | `1` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
| <a name="input_private_ip"></a> [private\_ip](#input\_private\_ip) | Fixed private IP for the gateway VNIC. Must sit in subnet\_id's CIDR outside OCI's reserved first-2/last-1 hosts and clear of the OKE node range. Pinning it makes the hub's uplink dial address plan-known (no two-pass PENDING apply) and stable across VM recreation (the hub never dials a stale IP). Empty = DHCP. | `string` | `""` | no |
| <a name="input_shape"></a> [shape](#input\_shape) | Compute shape (flex shapes are sized by ocpus/memory\_in\_gbs) | `string` | `"VM.Standard.E4.Flex"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt. | `string` | `""` | no |
| <a name="input_tenancy_id"></a> [tenancy\_id](#input\_tenancy\_id) | OCID of the tenancy (root compartment) — the instance-principal dynamic group is tenancy-level and must live here. Required when enable\_instance\_principal = true. | `string` | `""` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |
| <a name="input_vcn_id"></a> [vcn\_id](#input\_vcn\_id) | OCID of the VCN the NSG is created in. Only required when enable\_nsg = true. | `string` | `""` | no |
| <a name="input_vm_image_ocid"></a> [vm\_image\_ocid](#input\_vm\_image\_ocid) | Boot image OCID. Empty = latest Canonical Ubuntu 24.04 platform image for the shape. | `string` | `""` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the Traefik VM and its network resources | `string` | `"traefik"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | OCID of the Traefik VM (the member security/oci-instance-principal's dynamic group matches by compartment) |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1) |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their public IP addresses (empty string when enable\_public\_ip = false) |
<!-- END_TF_DOCS -->
