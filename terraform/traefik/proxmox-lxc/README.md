# traefik/proxmox-lxc

Traefik Hub in a **Proxmox VE LXC container** — the container sibling of `traefik/proxmox-vm`. Same shared configuration (`traefik/shared` via Helm template), same Hub, same `:9443` multicluster uplink; it just runs in a container instead of a VM, so a Proxmox demo can have **one gateway per compute type** the way `aws` pairs `traefik-ec2`/`traefik-ecs` and `azure` pairs `traefik-vm`/`traefik-aci`.

## Why this module exists

Proxmox hosts two kinds of guest — QEMU VMs and LXC containers — but the house pattern for the unified-ingress demos is *one child gateway per compute type, each fronting only its own backends* (`traefik-<type>` → `whoami-<type>`). With only `traefik/proxmox-vm`, a single gateway ended up fronting both, which no sibling demo does. This module is the LXC half of that pair.

## Two deliberate differences from `traefik/proxmox-vm`

### 1. No cloud-init — `pct exec`, and a raw binary

A container has no cloud-init user-data channel, so the configuration is delivered the way `apps/whoami/proxmox` already delivers its own: `pct push` + `pct exec` over SSH **to the Proxmox node** (`var.node_ssh` — the user needs passwordless sudo, since `pct` is root-only and lives in `/usr/sbin`).

The Hub then runs as a **raw binary under systemd**, mirroring `traefik/cloud-init`'s non-preview path — which is what a container wants anyway. The binary is **extracted from the OCI image with `crane`** rather than run under docker: docker-in-an-unprivileged-LXC means fighting overlayfs and nesting for no benefit, and the Hub image is single-binary (`ENTRYPOINT /traefik-hub`).

> `var.custom_image_*` should name **the same build the rest of the mesh runs**. A child on a different Hub version cannot join the uplink, so pulling a released tarball instead of extracting the mesh's image is *not* equivalent.

### 2. The plugin discovers everything — the **routes** are what separate the compute types

This module runs the same **[`NX211/traefik-proxmox-provider`](https://github.com/NX211/traefik-proxmox-provider)** plugin as the VM child (`var.proxmox_plugin`). That plugin has **no node/type/tag filter**: it polls the PVE API and routes *every* guest labelled `traefik.enable=true`, cluster-wide. Both children therefore discover **both** compute types, and that is expected and unavoidable.

**The separation is enforced one level up, in `var.file_provider_config`:** advertise only the LXC services here, and only the VM services on the VM child. Neither references the other's, and that is the *only* thing keeping the compute types apart — a foreign uplink in either child's file config silently re-merges them. Discovered-but-unrouted guests just sit there (the plugin also mints a per-guest auto-router, rule ``Host(`<guest-name>`)``, that nothing resolves — harmless).

## The address must be static

`var.ip_address` is **required**, and this is the one thing the plugin cannot solve for you. The hub's multicluster `children` map is terraform configuration, so it must dial `https://<this gateway>:9443` at an address known **at plan time** — and a container has no guest agent, so PVE never reports its DHCP lease back to terraform. The plugin discovers *backends*; it cannot tell the hub where its *children* are.

Going static has a consequence worth knowing: **a static guest gets no DHCP, and therefore no lab resolver.** Without `var.dns_servers` the container inherits the PVE host's public resolvers, and anything pointing at a lab hostname (an OTLP collector, say) resolves to the wrong address and silently fails — the gateway serves traffic perfectly and simply never appears in the service graph. `var.dns_servers` defaults to `[var.gateway]`, which is where dnsmasq listens on the demos' bridge.

## Usage

```hcl
module "lxc_traefik" {
  source = "../../terraform/traefik/proxmox-lxc"

  node_name            = "pve"
  bridge               = "vmbr1"
  lxc_template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"

  # Static: the hub dials this for the uplink. Keep it outside the DHCP pool.
  ip_address = "10.10.10.50/24"
  gateway    = "10.10.10.1"

  node_ssh = {
    host        = "pve.lab"
    user        = "proxmox" # needs passwordless sudo — pct is root-only
    private_key = file("~/.ssh/id_ed25519")
  }

  traefik_hub_token   = var.traefik_hub_token
  enable_offline_mode = true

  # Same Hub build as every other gateway in the mesh.
  custom_image_registry   = "ghcr.io"
  custom_image_repository = "zalbiraw/traefik-hub"
  custom_image_tag        = "demo-proxmox"

  otlp_service_name = "traefik-lxc" # its node in the service graph

  proxmox_plugin = {
    api_endpoint = "https://pve.lab:8006"
    api_token_id = "traefik@pve!discovery"
  }
  proxmox_api_token = var.discovery_token_secret

  multicluster_provider = { enabled = true }
  custom_ports = {
    lxcuplink = { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } }
  }

  # THE ENFORCEMENT POINT — only LXC services here.
  file_provider_config = yamlencode({
    http = {
      uplinks = { lxc-whoami = { entryPoints = ["lxcuplink"] } }
      routers = { lxc-whoami = { rule = "PathPrefix(`/`)", service = "lxc-whoami@plugin-proxmox", uplinks = ["lxc-whoami"] } }
    }
  })
}
```

The hub then dials `module.lxc_traefik.uplink_address` as a multicluster child, and surfaces the advertised services as `<uplink>@multicluster`.

## Requirements

- A **systemd Debian LXC template** on the node (`pveam download local debian-12-standard_*_amd64.tar.zst`) — the Hub rides its init.
- **Node SSH with passwordless sudo** — the same access the bpg provider's snippet upload already needs.
- **Outbound internet from the container** — `crane` (GitHub) + the image (registry) + the Yaegi plugin (`plugins.traefik.io`, downloaded at start, or Traefik exits).
- A **read-only PVE API token** for the plugin (Proxmox has no ambient identity).

Consumed by [`demos/proxmox-unified-ingress`](../../../demos/proxmox-unified-ingress).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | >= 0.60.0, < 1.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | >= 0.60.0, < 1.0.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [proxmox_virtual_environment_container.traefik](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_container) | resource |
| [terraform_data.provision](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Default gateway for the static address — normally the internal bridge's own IP. | `string` | n/a | yes |
| <a name="input_ip_address"></a> [ip\_address](#input\_ip\_address) | STATIC CIDR for the gateway container, e.g. "10.10.10.50/24". Required: the hub dials https://<ip>:9443 for the multicluster uplink, so the address must be known at plan time — and a container reports no DHCP lease back to terraform (no guest agent), so DHCP would leave the hub with nothing to dial. Keep it outside any DHCP pool on the bridge. | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Proxmox VE node the gateway container runs on. | `string` | n/a | yes |
| <a name="input_node_ssh"></a> [node\_ssh](#input\_node\_ssh) | SSH access to the Proxmox NODE, used to `pct push`/`pct exec` the Hub install into the container (LXC has no cloud-init user-data path). The user needs passwordless sudo — pct is root-only. | <pre>object({<br/>    host        = string<br/>    user        = optional(string, "root")<br/>    private_key = string<br/>  })</pre> | n/a | yes |
| <a name="input_bridge"></a> [bridge](#input\_bridge) | Linux bridge the container joins — the same guest network the whoami containers and the hub sit on, since the hub dials this gateway's uplink across it. | `string` | `"vmbr0"` | no |
| <a name="input_container_name"></a> [container\_name](#input\_container\_name) | Hostname of the gateway container. Name it for the compute type it fronts (e.g. traefik-lxc) — PVE keys guests on VMID, not name, so a duplicate name is not an error, just an ambiguous `pct list` and dashboard. | `string` | `"traefik-lxc"` | no |
| <a name="input_crane_version"></a> [crane\_version](#input\_crane\_version) | go-containerregistry release whose static `crane` binary extracts the Hub binary out of the OCI image (no docker daemon in the container). | `string` | `"v0.20.2"` | no |
| <a name="input_custom_arguments"></a> [custom\_arguments](#input\_custom\_arguments) | Extra Traefik CLI arguments. | `list(string)` | `[]` | no |
| <a name="input_custom_envs"></a> [custom\_envs](#input\_custom\_envs) | Extra environment variables for the Hub process. | `list(object({ name = string, value = string }))` | `[]` | no |
| <a name="input_custom_image_registry"></a> [custom\_image\_registry](#input\_custom\_image\_registry) | Registry of the image the Hub binary is EXTRACTED from. Must be the same build the rest of the mesh runs — a child on a different Hub version cannot join the uplink. | `string` | `""` | no |
| <a name="input_custom_image_repository"></a> [custom\_image\_repository](#input\_custom\_image\_repository) | Repository of the image the Hub binary is extracted from. | `string` | `""` | no |
| <a name="input_custom_image_tag"></a> [custom\_image\_tag](#input\_custom\_image\_tag) | Tag of the image the Hub binary is extracted from. | `string` | `""` | no |
| <a name="input_custom_plugins"></a> [custom\_plugins](#input\_custom\_plugins) | Extra Traefik plugins beyond the proxmox discovery plugin (which has its own proxmox\_plugin variable). | `any` | `{}` | no |
| <a name="input_custom_ports"></a> [custom\_ports](#input\_custom\_ports) | Extra entrypoints. Carries the multicluster uplink, e.g. { lxcuplink = { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } } }. Typed `any` because that shape is nested. | `any` | `{}` | no |
| <a name="input_dashboard_entrypoints"></a> [dashboard\_entrypoints](#input\_dashboard\_entrypoints) | Entrypoints the dashboard router binds. | `list(string)` | <pre>[<br/>  "traefik"<br/>]</pre> | no |
| <a name="input_dashboard_insecure"></a> [dashboard\_insecure](#input\_dashboard\_insecure) | Serve the dashboard without auth (lab default). | `bool` | `true` | no |
| <a name="input_dashboard_match_rule"></a> [dashboard\_match\_rule](#input\_dashboard\_match\_rule) | Router rule for the dashboard. | `string` | `""` | no |
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Datastore backing the container's root filesystem. | `string` | `"local-lvm"` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Root filesystem size (GB). The extracted Hub binary is ~17MB plus crane; 4GB is ample. | `number` | `4` | no |
| <a name="input_dns_search_domain"></a> [dns\_search\_domain](#input\_dns\_search\_domain) | Optional search domain for the container's resolver. | `string` | `""` | no |
| <a name="input_dns_servers"></a> [dns\_servers](#input\_dns\_servers) | Resolvers for the container. MUST be the lab resolver (the dnsmasq on the bridge that answers *.<domain> with the INTERNAL k3s address), not a public one. Because the address is static there is no DHCP lease to carry the lab resolver, so without this the container inherits the PVE host's public resolvers, resolves collector.<domain> to the box's PUBLIC ip via dns-traefiker, hairpins, and silently ships no telemetry. Defaults to [gateway] — on the demos' bridge, dnsmasq listens on the gateway address itself. | `list(string)` | `[]` | no |
| <a name="input_enable_access_logs"></a> [enable\_access\_logs](#input\_enable\_access\_logs) | Enable access logs. | `bool` | `true` | no |
| <a name="input_enable_ai_gateway"></a> [enable\_ai\_gateway](#input\_enable\_ai\_gateway) | Enable the AI Gateway. | `bool` | `false` | no |
| <a name="input_enable_api_gateway"></a> [enable\_api\_gateway](#input\_enable\_api\_gateway) | Run the API Gateway (Hub) rather than plain Traefik. | `bool` | `true` | no |
| <a name="input_enable_dashboard"></a> [enable\_dashboard](#input\_enable\_dashboard) | Serve the Traefik dashboard. | `bool` | `true` | no |
| <a name="input_enable_debug"></a> [enable\_debug](#input\_enable\_debug) | Debug mode. | `bool` | `false` | no |
| <a name="input_enable_mcp_gateway"></a> [enable\_mcp\_gateway](#input\_enable\_mcp\_gateway) | Enable the MCP Gateway. | `bool` | `false` | no |
| <a name="input_enable_offline_mode"></a> [enable\_offline\_mode](#input\_enable\_offline\_mode) | Run the Hub OFFLINE (license carries offline:true; no reporting to hub.traefik.io) — the natural mode for an air-gap-ish lab. | `bool` | `false` | no |
| <a name="input_enable_otlp_access_logs"></a> [enable\_otlp\_access\_logs](#input\_enable\_otlp\_access\_logs) | Ship access logs over OTLP. | `bool` | `false` | no |
| <a name="input_enable_otlp_application_logs"></a> [enable\_otlp\_application\_logs](#input\_enable\_otlp\_application\_logs) | Ship application logs over OTLP. | `bool` | `false` | no |
| <a name="input_enable_otlp_metrics"></a> [enable\_otlp\_metrics](#input\_enable\_otlp\_metrics) | Ship metrics over OTLP. | `bool` | `false` | no |
| <a name="input_enable_otlp_traces"></a> [enable\_otlp\_traces](#input\_enable\_otlp\_traces) | Ship traces over OTLP. | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Expose the Prometheus endpoint. | `bool` | `false` | no |
| <a name="input_file_provider_config"></a> [file\_provider\_config](#input\_file\_provider\_config) | The file provider's dynamic config (YAML). THIS is what makes this the LXC gateway: the plugin discovers every guest indiscriminately, so the compute-type separation is enforced here — advertise ONLY the LXC services (e.g. lxc-whoami@plugin-proxmox) and never the VM ones. Also where uplinks are declared for the hub to surface as <uplink>@multicluster. | `string` | `""` | no |
| <a name="input_file_provider_path"></a> [file\_provider\_path](#input\_file\_provider\_path) | Directory the file provider watches inside the container. | `string` | `"/etc/traefik-hub/dynamic"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Traefik log level. | `string` | `"INFO"` | no |
| <a name="input_lxc_template_file_id"></a> [lxc\_template\_file\_id](#input\_lxc\_template\_file\_id) | OS template file ID, e.g. "local:vztmpl/debian-12-standard\_12.7-1\_amd64.tar.zst". Must be a systemd Debian template — the Hub rides its init. | `string` | `""` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | RAM (MB) for the gateway container. | `number` | `1024` | no |
| <a name="input_multicluster_provider"></a> [multicluster\_provider](#input\_multicluster\_provider) | Multicluster provider config. { enabled = true } makes this a CHILD the hub can dial. | `any` | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPUs for the gateway container. | `number` | `2` | no |
| <a name="input_otlp_address"></a> [otlp\_address](#input\_otlp\_address) | OTLP endpoint this gateway ships to (the hub collector's ingress). Must be resolvable AND trusted from inside the container. | `string` | `""` | no |
| <a name="input_otlp_service_name"></a> [otlp\_service\_name](#input\_otlp\_service\_name) | service.name this gateway reports as — its node in the Tempo service graph. Name it for the compute type it fronts (traefik-lxc), pairing with its backend (whoami-lxc) the way the sibling demos pair traefik-<type> -> whoami-<type>. | `string` | `"traefik-lxc"` | no |
| <a name="input_proxmox_api_token"></a> [proxmox\_api\_token](#input\_proxmox\_api\_token) | Secret half of the PVE API token the plugin discovers with (Proxmox has no ambient identity, so this is explicit). Use the read-only discovery token — demo-grade in the process args either way. | `string` | `""` | no |
| <a name="input_proxmox_plugin"></a> [proxmox\_plugin](#input\_proxmox\_plugin) | NX211 traefik-proxmox-provider config — the same runtime Yaegi plugin the VM child runs, so Traefik downloads it from plugins.traefik.io at start (the container NEEDS outbound internet or Traefik exits). It discovers EVERY guest labelled traefik.enable=true and cannot be scoped by node/type/tag, so this gateway sees the VM guests too; that is expected. What makes this the LXC gateway is that file\_provider\_config only advertises the LXC services. | <pre>object({<br/>    enabled          = optional(bool, true)<br/>    version          = optional(string, "v0.8.1")<br/>    poll_interval    = optional(string, "30s")<br/>    api_endpoint     = string<br/>    api_token_id     = string<br/>    api_validate_ssl = optional(bool, false)<br/>    api_logging      = optional(string, "")<br/>  })</pre> | <pre>{<br/>  "api_endpoint": "",<br/>  "api_token_id": "",<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_traefik_chart_version"></a> [traefik\_chart\_version](#input\_traefik\_chart\_version) | Traefik Helm chart version the shared module templates the static config from. | `string` | `"40.3.0"` | no |
| <a name="input_traefik_hub_preview_tag"></a> [traefik\_hub\_preview\_tag](#input\_traefik\_hub\_preview\_tag) | Traefik Hub preview tag. | `string` | `""` | no |
| <a name="input_traefik_hub_tag"></a> [traefik\_hub\_tag](#input\_traefik\_hub\_tag) | Traefik Hub release tag. | `string` | `"v3.20.4"` | no |
| <a name="input_traefik_hub_token"></a> [traefik\_hub\_token](#input\_traefik\_hub\_token) | Traefik Hub license token. Delivered via /etc/traefik-hub/env (0600) and injected as --hub.token=$HUB\_TOKEN by systemd, so it never appears in the process args. | `string` | `""` | no |
| <a name="input_traefik_tag"></a> [traefik\_tag](#input\_traefik\_tag) | Traefik OSS image tag. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_id"></a> [container\_id](#output\_container\_id) | PVE id of the gateway container. |
| <a name="output_image_full"></a> [image\_full](#output\_image\_full) | The image the Hub binary was extracted from — should match every other gateway in the mesh (a child on a different Hub version cannot join the uplink). |
| <a name="output_instances"></a> [instances](#output\_instances) | Gateway container details, shaped like the sibling gateway modules' outputs. |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | The gateway container's guest IP (the pinned ip\_address, minus its /prefix). Known at PLAN time — this is the address the hub dials for the multicluster uplink. |
| <a name="output_uplink_address"></a> [uplink\_address](#output\_uplink\_address) | Ready-made multicluster child address for the hub's children map, e.g. https://10.10.10.50:9443. The uplink serves Traefik's default self-signed cert, so the hub dials it with serversTransport.insecureSkipVerify. |
<!-- END_TF_DOCS -->
