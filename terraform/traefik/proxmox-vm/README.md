# traefik/proxmox-vm

Traefik Hub on a **Proxmox VE VM** — the on-prem sibling of `traefik/vsphere-vm` / `traefik/ec2` / `traefik/azure-vm`. Clones a user-provided **cloud-init-enabled Ubuntu cloud-image template**, extracts its Traefik configuration from `traefik/shared` (via Helm template) and boots it with the shared `traefik/cloud-init` template — as a systemd binary, or as a docker container when `enable_preview_mode = true`.

## The gateway provider is an open-source PLUGIN, not a hub provider

Unlike every sibling, discovery here is **[`github.com/NX211/traefik-proxmox-provider`](https://github.com/NX211/traefik-proxmox-provider)** — a community **catalog provider plugin** that any stock Traefik/Hub image loads at runtime via Yaegi. No custom gateway build is needed for discovery. `var.proxmox_plugin` renders the plugin's static config as CLI flags:

```
--experimental.plugins.proxmox.moduleName=github.com/NX211/traefik-proxmox-provider
--experimental.plugins.proxmox.version=v0.8.1
--providers.plugin.proxmox.pollInterval=30s
--providers.plugin.proxmox.apiEndpoint=https://pve.example.com:8006
--providers.plugin.proxmox.apiTokenId=root@pam!traefik
--providers.plugin.proxmox.apiToken=***          # var.proxmox_api_token
--providers.plugin.proxmox.apiValidateSSL=false  # self-signed PVE certs are the lab norm
```

Traefik **downloads the plugin from plugins.traefik.io at start** — the VM needs outbound internet or Traefik exits. The plugin's dynamic config lands under the **`@plugin-proxmox`** provider namespace (Traefik prefixes plugin providers with `plugin-`), so file-provider routers reference discovered services as `<name>@plugin-proxmox`.

What the plugin does (cluster-wide, all nodes): polls the PVE API, reads each **running** QEMU VM's and LXC container's **Notes/description field line by line** for `traefik.key=value` labels (`traefik.enable=true` mandatory — see `apps/whoami/proxmox`), resolves guest IPs (QEMU guest agent for VMs; the lxc interfaces endpoint for containers), and emits routers + services. Honest semantics to plan around (verified against the v0.8.1 source):

- **One server per service, no merging** — same-named services on two guests overwrite each other. Compose multi-guest spreads with a `weighted` file-provider service.
- **No `loadbalancer.strategy` label** — supported service options are port/scheme/url/ip, passHostHeader, healthcheck, sticky cookie, responseForwarding, serversTransport.
- **Every enabled guest gets a router** (default rule ``Host(`<guest-name>`)``) — there is no routerless mode; expect harmless auto-routers next to your file-provider ones.

**Credentials are explicit** — Proxmox has no ambient identity, so the plugin takes a **PVE API token** (`api_token_id` in the object, the secret in `var.proxmox_api_token`). Create a read-only role per the plugin README: `VM.Audit,Sys.Audit,Datastore.Audit` plus `VM.GuestAgent.Audit` on PVE 9 (`VM.Monitor` on PVE 8). The token lands in the VM's systemd unit / container args — demo-grade; don't reuse an admin credential.

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

  proxmox_plugin = {
    api_endpoint = "https://pve.lab.example.com:8006"
    api_token_id = "traefik@pve!discovery"
  }
  proxmox_api_token = var.plugin_api_token

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

- The `bpg/proxmox` provider with clone rights **and** its `ssh {}` block (the cloud-init snippet uploads over SSH) — plus the separate read-only plugin token above; they can differ.
- A **cloud-init-enabled Ubuntu cloud-image template with `qemu-guest-agent` baked in** (the agent reports the guest IP the parent dials — this module's user-data is the shared Traefik template, so it can't install the agent itself). DHCP on the bridge; `helm` on the machine running terraform (config extraction via `helm template`); outbound internet from the VM (Hub binary/image + the plugin download).

## Notes

- `enable_dashboard_discovery` (default on) self-registers the VM's dashboard through its own Notes labels (`dashboard` router on `@plugin-proxmox`); disable it when a file-rule uplink advertises the dashboard instead.
- Outputs mirror the VM siblings (`instances` / `private_ips` / `public_ips`) so demo code reads identically — on Proxmox both IP maps carry the same guest address.
- The cloud-init snippet is hash-named and the VM `replace_triggered_by`s it — config changes recreate the VM (cloud-init runs on first boot only).
