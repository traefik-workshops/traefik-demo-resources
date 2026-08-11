# compute/proxmox/lxc

The shared **LXC container primitive** on Proxmox VE. Creates an unprivileged, nesting-enabled container (so systemd runs inside) from a Debian OS template on a Linux bridge.

Both `traefik/proxmox-lxc` (one statically-addressed gateway container) and `apps/whoami/proxmox` (N DHCP whoami containers) compose this module — the resource that used to be duplicated in both. It owns **no role config**: the in-container install (the Hub binary / the whoami binary, delivered via `pct push` + `pct exec` over SSH to the node) stays in the callers, which read the container id from the `instances` output and provision against it.

Addressing is per-instance: `ip_address = "dhcp"` (the default — whoami backends, whose leases the proxmox plugin discovers via the PVE API) or a static CIDR plus `gateway` and an optional `dns` block (the gateway child, whose `:9443` uplink the hub dials at a plan-known address).

## Example usage

```hcl
module "lxc" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/proxmox/lxc?ref=v6.1.4"

  node_name        = "pve"
  datastore_id     = "local-lvm"
  template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"

  instances = {
    "traefik-lxc" = {
      description = "traefik.enable=true"
      ip_address  = "10.10.10.50/24"
      gateway     = "10.10.10.1"
      dns         = { servers = ["10.10.10.1"], domain = "lab.example" }
    }
  }
}
```

## Prerequisites

- A `bpg/proxmox` provider with node access (the callers reach the container over SSH to `pct exec` the install).
- The OS template must be a systemd Debian template.
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
