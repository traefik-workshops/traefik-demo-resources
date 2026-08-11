# traefik/gce

Traefik Hub on one GCE VM — the GCP sibling of `traefik/ec2`/`traefik/azure-vm` and a **multicluster CHILD**: it joins a Hub parent over a `:9443` uplink and discovers local whoami VMs via its own `hub.providers.gce` provider.

Composes `traefik/shared` (extracted Helm config) and `traefik/cloud-init` exactly like `traefik/ec2`. The gce provider ships only in a preview image (`ghcr.io/zalbiraw/traefik-hub`), so the demo sets `enable_preview_mode = true` + `custom_image_*` and the VM runs the image as a docker container (`--network host`, so the metadata server/ADC and the uplink work).

Auth is a module-created **service account attached to the VM** (Application Default Credentials) + a `roles/compute.viewer` project binding (`enable_viewer_role`) — no key file. The module appends the provider flags (`--hub.providers.gce.projectID/zones/ipMode/serviceNameLabel/configEndpoint/...`) to `custom_arguments`; `project_id` defaults from `data.google_client_config`.

**Discovery contract (mirrors `traefik/vsphere-vm`):** an instance carries ONLY a service name — the value of one GCE label (`gce_provider.service_name_label`, provider default `traefik-service`; values are lowercase `[a-z0-9_-]` and single-valued, so one instance backs one service). All routing intent (routers, services, middlewares, uplinks) lives in ONE base configuration the provider loads from `gce_provider.config_endpoint` (a GitOps URL — see `terraform/config-server/git`) or `gce_provider.filename` — exactly one, the provider cannot boot without it. Base services declare `loadBalancer.scheme`/`port` but no servers; the provider injects one server per discovered instance. There is no `exposedByDefault`/`constraints`/`defaultRule` and no per-VM metadata blob any more.

## Example usage

```hcl
module "gce_traefik" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/gce?ref=v6.1.4"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  zone    = "us-central1-a"
  network = module.gke.network # or "default"

  # The gce provider isn't in a Hub release — run the custom image as a container.
  enable_preview_mode     = true
  custom_image_registry   = "docker.io"
  custom_image_repository = "zalbiraw/traefik-hub"
  custom_image_tag        = "latest"

  # Hub uplink entrypoint on :9443 (TLS; the parent verifies with insecureSkipVerify).
  multicluster_provider = { enabled = true }
  custom_ports = {
    gceuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }

  # The provider's base configuration — polled from a GitOps URL (the hub's
  # git-config-server, see terraform/config-server/git). Instances labeled
  # `traefik-service: whoami` become the servers of the `whoami` service; the
  # router + uplink advertise it over the :9443 uplink entrypoint. Changing
  # routing intent = pushing a new document, never replacing the VM.
  gce_provider = {
    config_endpoint = "https://git.example.com/config/gce/dynamic.yaml"
  }
}
```

The document served at that URL (no servers — the provider injects them):

```yaml
http:
  uplinks:
    gce-whoami:
      entryPoints: [gceuplink]
  routers:
    gce-whoami:
      rule: PathPrefix(`/`)
      service: whoami
      uplinks: [gce-whoami]
  services:
    whoami:
      loadBalancer:
        port: "80"
```

## Prerequisites

- GCP credentials with Compute/Service Account permissions **and IAM-grant rights** on the project (or set `enable_viewer_role = false` and grant `roles/compute.viewer` yourself).
- A joinable VPC network; `:9443` must be reachable in-network. The module's own firewall rule (`enable_firewall`, default on) opens 80/443/8080/9443 from `firewall_source_ranges` to the VM — the GCP analog of `compute/azure/vnet`'s `extra_ingress_ports = [9443]`.
- `helm` on the machine running terraform (`traefik/shared` extracts config via `helm template`).

## Notes

- One VM (no replica set) — the parent dials `values(module.gce_traefik.private_ips)[0]` on `:9443`.
- The gateway VM never self-registers: it carries no `service_name_label` label, so its own provider ignores it. Advertise the dashboard through the base configuration (a router on `api@internal`).
- A gateway that discovers by another mechanism (e.g. the docker-provider leg) sets `gce_provider = { enabled = false }` — an enabled gce provider requires a base-config source and cannot boot bare.
- There is deliberately no `traefik/cloudrun` sibling: Cloud Run can't host a raw `:9443` uplink listener, so the cloudRun-discovering child runs in-cluster on GKE instead.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [google_project_iam_member.viewer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_service_account.traefik](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [random_id.sa_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
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
| <a name="input_enable_firewall"></a> [enable\_firewall](#input\_enable\_firewall) | Create a firewall rule opening firewall\_ports to the VM from firewall\_source\_ranges (mirrors compute/azure/vnet's NSG + extra\_ingress\_ports). Disable when the network already allows it (e.g. default network's default-allow-internal). | `bool` | `true` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable MCP Gateway (Claude, etc.) | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Enable Traefik Hub Offline mode | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Enable OTLP access logs | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Enable OTLP application logs | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Enable OTLP metrics | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Enable OTLP traces | `bool` | `false` | no |
| <a name="input_enable_preview_mode"></a> [enable\_preview\_mode](#input\_enable\_preview\_mode) | Enable Traefik Hub Preview features (runs the image as a docker container — required for provider builds not yet in a Hub release, e.g. gce) | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Prometheus metrics | `bool` | `false` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Attach an ephemeral public IP to the VM. Off by default — the parent dials the private IP (same network). | `bool` | `false` | no |
| <a name="input_enable_viewer_role"></a> [enable\_viewer\_role](#input\_enable\_viewer\_role) | Grant roles/compute.viewer on the provider's project to the VM's service account (requires the caller to hold IAM-grant rights, e.g. Owner/Project IAM Admin). | `bool` | `true` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files to write to the VM at cloud-init time | <pre>list(object({<br/>    path    = string<br/>    content = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_labels"></a> [extra\_labels](#input\_extra\_labels) | Extra GCE labels to apply to the VM. Leave the provider's service\_name\_label out of it unless this gateway should be discovered as a server of that service itself. | `map(string)` | `{}` | no |
| <a name="input_extra_runcmd"></a> [extra\_runcmd](#input\_extra\_runcmd) | Extra shell blocks appended to cloud-init runcmd, after Docker is installed and before traefik-hub starts. Used to run workload containers on the gateway VM itself (the docker-provider leg). | `list(string)` | `[]` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | YAML configuration for Traefik file provider | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Path where the file provider config is mounted | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_firewall_ports"></a> [firewall\_ports](#input\_firewall\_ports) | TCP ports the firewall rule opens on the VM. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials. | `list(number)` | <pre>[<br/>  80,<br/>  443,<br/>  8080,<br/>  9443<br/>]</pre> | no |
| <a name="input_firewall_source_ranges"></a> [firewall\_source\_ranges](#input\_firewall\_source\_ranges) | Source CIDR ranges allowed by the firewall rule. Default covers the default network (10.128.0.0/9) and typical GKE node/pod ranges. | `list(string)` | <pre>[<br/>  "10.0.0.0/8"<br/>]</pre> | no |
| <a name="input_gce_provider"></a> [gce\_provider](#input\_gce\_provider) | Traefik Hub gce provider configuration (hub.providers.gce). The provider follows the<br/>vsphere contract: a machine carries ONLY a service name and the routing intent lives<br/>in a base configuration, not in per-VM labels or metadata blobs.<br/><br/>  service\_name\_label  the GCE LABEL whose VALUE names the service an instance backs<br/>                      (provider default `traefik-service`). GCE label values are<br/>                      lowercase [a-z0-9\_-] and single-valued, so ONE instance backs<br/>                      ONE service; instances sharing a value merge into one LB.<br/>  config\_endpoint     URL the gateway polls for the base config (GitOps), OR<br/>  filename            a path to it on the gateway host. Exactly one.<br/><br/>The base config declares each service's loadBalancer (scheme default http, port<br/>REQUIRED) with NO servers — the provider injects one server per discovered instance.<br/>project\_id defaults to the caller's (data.google\_client\_config); zones empty = all<br/>zones. No credentialsFile/credentialsJSON: ADC resolves the VM's attached service<br/>account. | <pre>object({<br/>    enabled                     = optional(bool, true)<br/>    project_id                  = optional(string, "")<br/>    zones                       = optional(list(string), [])<br/>    ip_mode                     = optional(string, "private")<br/>    service_name_label          = optional(string, "")<br/>    config_endpoint             = optional(string, "")<br/>    config_insecure_skip_verify = optional(bool, false)<br/>    filename                    = optional(string, "")<br/>    refresh_seconds             = optional(number, null)<br/>  })</pre> | `{}` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level (DEBUG, INFO, WARN, ERROR) | `string` | `"INFO"` | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | GCE machine type | `string` | `"e2-medium"` | no |
| <a name="input_mount_docker_socket"></a> [mount\_docker\_socket](#input\_mount\_docker\_socket) | Bind /var/run/docker.sock into the preview-mode Traefik container so its docker provider can reach the local daemon. Root-equivalent access to the host, so leave it off for any gateway that is not the docker-provider leg. | `bool` | `false` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Traefik Hub multicluster provider configuration | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    pollInterval = optional(number, null)<br/>    pollTimeout  = optional(number, null)<br/>    children     = optional(any, {})<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_network"></a> [network](#input\_network) | VPC network the VM joins (the parent dials the VM's private IP :9443 in-network). Defaults to the project's default network — the same one compute/gcp/gke clusters sit on (see its `network` output). | `string` | `"default"` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP collector endpoint | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | Service name for telemetry | `string` | `"traefik"` | no |
| <a name="input_performance_tuning"></a> [performance\_tuning](#input\_performance\_tuning) | OS-level performance tuning parameters for high-throughput workloads | <pre>object({<br/>    # Systemd ulimits<br/>    limit_nofile = optional(number, 500000)<br/><br/>    # Sysctl network tuning<br/>    tcp_tw_reuse        = optional(number, 1)<br/>    tcp_timestamps      = optional(number, 1)<br/>    rmem_max            = optional(number, 16777216)<br/>    wmem_max            = optional(number, 16777216)<br/>    somaxconn           = optional(number, 4096)<br/>    netdev_max_backlog  = optional(number, 4096)<br/>    ip_local_port_range = optional(string, "1024 65535")<br/><br/>    # Go runtime tuning<br/>    gomaxprocs = optional(number, 0)   # 0 = use all CPUs<br/>    gogc       = optional(number, 100) # default GC target percentage<br/>    numa_node  = optional(number, -1)  # -1 = disabled, 0+ = pin to node<br/>  })</pre> | `{}` | no |
| <a name="input_private_ip"></a> [private\_ip](#input\_private\_ip) | Fixed internal IP for the gateway VM (network\_interface.network\_ip). Must sit in the instance's subnetwork range — on the default auto-mode network that range is region-fixed (us-central1 = 10.128.0.0/20). Pinning it makes the hub's uplink dial address plan-known (no two-pass PENDING apply) and stable across VM recreation. Empty = ephemeral. | `string` | `""` | no |
| <a name="input_service_account_id"></a> [service\_account\_id](#input\_service\_account\_id) | Account ID for the service account attached to the VM (ADC credential for the gce provider) | `string` | `"traefik-gce"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key authorized for the traefiker user on the gateway. Optional: empty keeps the demo password as the only credential, which works but makes every diagnostic script drive an interactive prompt. | `string` | `""` | no |
| <a name="input_subnetwork"></a> [subnetwork](#input\_subnetwork) | Subnetwork the VM joins. Empty = let GCP pick the network's subnet in the zone's region (works on auto-mode networks like `default`). | `string` | `""` | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version. 40.x renders the partial metrics.otlp block and ships multicluster support; 38.x is pre-multicluster (kept the spoke from joining a Hub mesh). | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview version tag | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub image tag. Multicluster (the uplink) ships in v3.20+; v3.19.0 silently can't join a Hub mesh. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS version tag | `string` | `"v3.7.4"` | no |
| <a name="input_vm_image"></a> [vm\_image](#input\_vm\_image) | Boot disk image (family or self link) | `string` | `"ubuntu-os-cloud/ubuntu-2404-lts-amd64"` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the Traefik VM, its network tag, and its firewall rule | `string` | `"traefik"` | no |
| <a name="input_zone"></a> [zone](#input\_zone) | GCE zone the VM is created in | `string` | `"us-central1-a"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1) |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their public IP addresses (empty string when enable\_public\_ip = false) |
| <a name="output_service_account_email"></a> [service\_account\_email](#output\_service\_account\_email) | Email of the service account attached to the VM (the gce provider's ADC credential) |
<!-- END_TF_DOCS -->
