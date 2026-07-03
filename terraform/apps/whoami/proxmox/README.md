# apps/whoami/proxmox

Provisions one or more Traefik `whoami` instances on **Proxmox VE guests** — the on-prem sibling of `apps/whoami/vsphere` / `apps/whoami/ec2` / `apps/whoami/gce`, targeting the open-source **[`NX211/traefik-proxmox-provider`](https://github.com/NX211/traefik-proxmox-provider)** Traefik plugin (see `traefik/proxmox-vm`). Two guest types per app:

- **`type = "vm"`** (default) — a QEMU clone of a cloud-init-enabled Ubuntu cloud-image template, docker-running the whoami fork via `whoami/cloud-init` like every sibling (default image: the OTel-instrumented `docker.io/zalbiraw/whoami`).
- **`type = "lxc"`** — a container from a Debian OS template, running the **upstream `traefik/whoami` binary** under systemd (see the honest limitations below).

## The workload config is LINE-format labels in the Notes field

The NX211 plugin reads each guest's **Notes/description field line by line** — one `traefik.key=value` per line, **NOT JSON** (the vsphere sibling), not dotted tags (EC2/Azure/OCI):

```
traefik.enable=true
traefik.http.services.whoami-1.loadbalancer.server.port=80
```

This module renders each app's `traefik_labels` map into that format. `traefik.enable=true` is mandatory (unlabeled guests are ignored); the parser lowercases keys.

**One service per guest — no server merging** (verified against the plugin source, v0.8.1): every labeled service gets exactly ONE server (the guest's IP), and a same-named service on a second guest **overwrites** the first. Unlike the vsphere/EC2 providers, identical labels on N replicas do NOT merge into an N-server service — give every guest **unique service names** and compose the spread upstream (e.g. a `weighted` file-provider service on the gateway; `demos/proxmox-unified-ingress` shows the pattern). Also note the plugin **always creates a router per guest** (default rule ``Host(`<guest-name>`)``) — harmless noise when your real routers live in file config.

## LXC support, honestly

Proxmox LXC containers have **no cloud-init user-data path**, so pure terraform can't provision inside them the way the QEMU clones are. This module's honest workaround: it **SSHes to the Proxmox node** (`node_ssh`) and `pct push` + `pct exec`s a setup script that installs the upstream `traefik/whoami` release binary and a systemd unit. Limitations:

- Requires **node SSH access** (the same access the bpg provider's snippet upload needs anyway).
- Runs the **upstream binary**, not the OTel fork (docker-only) — `OTEL_*` env vars are ignored; the body still shows `Hostname:`/`Name:`.
- The container's DHCP address is **never known to terraform** (`private_ip` is null in the output) — the plugin discovers container IPs itself via the PVE API.
- amd64 only (the release-tarball fetch).

## Example usage

```hcl
module "whoami_proxmox" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/apps/whoami/proxmox?ref=v4.3.0"

  node_name     = "pve"
  datastore_id  = "local-lvm"
  template_name = "ubuntu-24.04-cloudimg"

  lxc_template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  node_ssh             = { host = "pve.lab.example.com", private_key = file("~/.ssh/id_ed25519") }

  apps = {
    # UNIQUE service name per guest — the plugin does not merge servers.
    whoami-1 = {
      replicas = 1
      port     = 80
      name     = "whoami-qemu"
      traefik_labels = {
        "traefik.enable"                                          = "true"
        "traefik.http.services.whoami-1.loadbalancer.server.port" = "80"
      }
    }
    whoami-lxc = {
      replicas = 1
      type     = "lxc"
      port     = 80
      name     = "whoami-lxc"
      traefik_labels = {
        "traefik.enable"                                            = "true"
        "traefik.http.services.whoami-lxc.loadbalancer.server.port" = "80"
      }
    }
  }
}
```

## Prerequisites

- The `bpg/proxmox` provider with clone rights **and** its `ssh {}` block configured (snippet upload rides SSH; the PVE API has no snippet endpoint).
- For VMs: a **cloud-init-enabled Ubuntu cloud-image template with `qemu-guest-agent`** — the agent reports guest IPs to terraform AND to the plugin (on PVE 9 the plugin's token also needs the `VM.GuestAgent.Audit` privilege). DHCP on the bridge; outbound internet (docker pulls).
- For LXC: a Debian OS template on the node (`pveam download local debian-12-standard_...`), `node_ssh`, and outbound internet from the container (apt + the whoami release tarball).

## Notes

- Instance keys follow the siblings' `"<app>-<replica>"` scheme; guest names are cosmetic — routing names come from the labels.
- Terraform is 1.4+ for this module (`terraform_data` provisioners drive the LXC install).
