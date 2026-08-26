# compute/proxmox/lxc

The shared **LXC container primitive** on Proxmox VE. Creates an unprivileged, nesting-enabled container (so systemd runs inside) from a Debian OS template on a Linux bridge.

Both `traefik/proxmox-lxc` (one statically-addressed gateway container) and `apps/whoami/proxmox` (N DHCP whoami containers) compose this module — the resource that used to be duplicated in both. It owns **no role config**: the in-container install (the Hub binary / the whoami binary, delivered via `pct push` + `pct exec` over SSH to the node) stays in the callers, which read the container id from the `instances` output and provision against it.

Addressing is per-instance: `ip_address = "dhcp"` (the default — whoami backends, whose leases the proxmox plugin discovers via the PVE API) or a static CIDR plus `gateway` and an optional `dns` block (the gateway child, whose `:9443` uplink the hub dials at a plan-known address).

## Example usage

```hcl
module "lxc" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/proxmox/lxc?ref=v8.0.0"

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
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | >= 0.60.0, < 1.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | >= 0.60.0, < 1.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [proxmox_virtual_environment_container.this](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_container) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Name of the Proxmox VE node the containers are created on | `string` | n/a | yes |
| <a name="input_bridge"></a> [bridge](#input\_bridge) | Name of the Linux bridge each container's NIC (eth0) joins | `string` | `"vmbr0"` | no |
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Datastore backing the containers' root filesystems (e.g. local-lvm) | `string` | `"local-lvm"` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Root filesystem size (GB) per container | `number` | `4` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | Map of containers to create, keyed by container name (used as the initialization hostname). description is the guest Notes/description (null = unset). ip\_address is a CIDR for a STATIC address or "dhcp" (default); gateway is required alongside a static address and must be null for DHCP. dns (optional) writes an initialization dns block — required for static addresses that must reach a specific lab resolver. | <pre>map(object({<br/>    description = optional(string)<br/>    ip_address  = optional(string, "dhcp")<br/>    gateway     = optional(string)<br/>    dns = optional(object({<br/>      servers = list(string)<br/>      domain  = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | RAM (MB) per container | `number` | `1024` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPUs per container | `number` | `2` | no |
| <a name="input_template_file_id"></a> [template\_file\_id](#input\_template\_file\_id) | OS template file ID, e.g. "local:vztmpl/debian-12-standard\_12.7-1\_amd64.tar.zst". Must be a systemd Debian template — the workload rides its init. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the created containers with their details (keyed by container name). id is the PVE container id (the callers pct-exec against it). private\_ip/public\_ip are the pinned static IP for statically-addressed containers, or null for DHCP ones (no guest agent — discovered via the PVE API). |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of container names to their pinned static IP (minus the /prefix), or null for DHCP containers. |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of container names to their pinned static IP — identical to private\_ips (no public-IP concept on Proxmox; kept for sibling-parity). |
<!-- END_TF_DOCS -->
