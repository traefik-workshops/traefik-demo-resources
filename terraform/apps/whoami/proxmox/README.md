# apps/whoami/proxmox

Provisions one or more Traefik `whoami` instances on **Proxmox VE guests** — the on-prem sibling of `apps/whoami/vsphere` / `apps/whoami/ec2` / `apps/whoami/gce`, discovered by Traefik Hub's **native first-party Proxmox provider** (`--hub.providers.proxmox.*`; see `traefik/proxmox-vm`). Two guest types per app:

- **`type = "vm"`** (default) — a QEMU clone of a cloud-init-enabled Ubuntu cloud-image template, docker-running the whoami fork via `whoami/cloud-init` like every sibling (default image: the OTel-instrumented `ghcr.io/zalbiraw/whoami`).
- **`type = "lxc"`** — a container from a Debian OS template, running the **upstream `traefik/whoami` binary** under systemd (see the honest limitations below).

## The workload config is LINE-format labels in the Notes field

The native provider reads each guest's **Notes/description field line by line** — one `traefik.key=value` per line, **NOT JSON** (the vsphere sibling), not dotted tags (EC2/Azure/OCI):

```
traefik.enable=true
traefik.http.services.whoami-1.loadbalancer.server.port=80
```

This module renders each app's `traefik_labels` map into that format. `traefik.enable=true` is mandatory (unlabeled guests are ignored); the parser lowercases keys.

**One service per guest — no server merging**: every labeled service gets exactly ONE server (the guest's IP), and a same-named service on a second guest **overwrites** the first. Unlike the vsphere/EC2 providers, identical labels on N replicas do NOT merge into an N-server service — give every guest **unique service names** and compose the spread upstream (e.g. a `weighted` file-provider service on the gateway; `demos/proxmox-unified-ingress` shows the pattern). The native provider also **mints a router per guest** (default rule ``Host(`<guest-name>`)``) — harmless noise when your real routers live in file config.

## LXC support, honestly

Proxmox LXC containers have **no cloud-init user-data path**, so pure terraform can't provision inside them the way the QEMU clones are. This module's honest workaround: it **SSHes to the Proxmox node** (`node_ssh`) and `pct push` + `pct exec`s a setup script that installs the upstream `traefik/whoami` release binary and a systemd unit. Limitations:

- Requires **node SSH access** (the same access the bpg provider's snippet upload needs anyway).
- Runs the **upstream binary**, not the OTel fork (docker-only) — `OTEL_*` env vars are ignored; the body still shows `Hostname:`/`Name:`.
- The container's DHCP address is **never known to terraform** (`private_ip` is null in the output) — the native provider discovers container IPs itself via the PVE API.
- amd64 only (the release-tarball fetch).

## Example usage

```hcl
module "whoami_proxmox" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/proxmox?ref=v5.0.1"

  node_name     = "pve"
  datastore_id  = "local-lvm"
  template_name = "ubuntu-24.04-cloudimg"

  lxc_template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  node_ssh             = { host = "pve.lab.example.com", private_key = file("~/.ssh/id_ed25519") }

  apps = {
    # UNIQUE service name per guest — the native provider does not merge servers.
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
- For VMs: a **cloud-init-enabled Ubuntu cloud-image template with `qemu-guest-agent`** — the agent reports guest IPs to terraform AND to the native provider (on PVE 9 the provider's token also needs the `VM.GuestAgent.Audit` privilege). DHCP on the bridge; outbound internet (docker pulls).
- For LXC: a Debian OS template on the node (`pveam download local debian-12-standard_...`), `node_ssh`, and outbound internet from the container (apt + the whoami release tarball).

## Notes

- Instance keys follow the siblings' `"<app>-<replica>"` scheme; guest names are cosmetic — routing names come from the labels.
- Terraform is 1.4+ for this module (`terraform_data` provisioners drive the LXC install).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.lxc_whoami](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Datastore backing the guests' disks and cloud-init drives (e.g. local-lvm) | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Name of the Proxmox VE node the guests are created on | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to Proxmox guests. Same shape as apps/whoami/vsphere plus a `type` field: { name = { replicas, type ("vm"\|"lxc", default vm), port, name, environment, traefik\_labels } }. `traefik_labels` (dotted Traefik label -> value) is rendered as LINE-format `traefik.key=value` labels (one per line) into the guest's Notes/description. NB the native provider registers ONE server per guest and same-named services overwrite each other, so give each guest UNIQUE service names (compose spreads upstream with a weighted file-provider service) — i.e. ONE APP PER GUEST with replicas = 1, which the validation below enforces. | `any` | `{}` | no |
| <a name="input_bridge"></a> [bridge](#input\_bridge) | Name of the Linux bridge the guests' NICs join (DHCP is assumed; the Traefik child dials each guest's IP) | `string` | `"vmbr0"` | no |
| <a name="input_cpu_type"></a> [cpu\_type](#input\_cpu\_type) | QEMU CPU type for VMs. `host` passes the node's CPU through; pick a named model when live migration matters. | `string` | `"host"` | no |
| <a name="input_crane_version"></a> [crane\_version](#input\_crane\_version) | go-containerregistry release whose static `crane` binary the LXC setup fetches to export lxc\_whoami\_image's rootfs (no docker needed on the node or in the container). | `string` | `"v0.20.2"` | no |
| <a name="input_disk_interface"></a> [disk\_interface](#input\_disk\_interface) | Interface of the template's disk to resize (the standard cloud-image import recipe attaches it as scsi0) | `string` | `"scsi0"` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | VM disk size in GB. Must be at least the template's disk (Proxmox can't shrink on clone). | `number` | `20` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami (docker -e on VMs, the systemd unit on LXC), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. With the default lxc\_whoami\_image (the fork), the LXC binary honors OTEL\_* too; only the upstream-release fallback ignores them. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_lxc_disk_size"></a> [lxc\_disk\_size](#input\_lxc\_disk\_size) | Root filesystem size in GB for LXC containers | `number` | `8` | no |
| <a name="input_lxc_template_file_id"></a> [lxc\_template\_file\_id](#input\_lxc\_template\_file\_id) | OS template file ID LXC apps are created from, e.g. "local:vztmpl/debian-12-standard\_12.7-1\_amd64.tar.zst" (a systemd Debian template — the whoami unit rides its init). Required when any app has type = "lxc". | `string` | `""` | no |
| <a name="input_lxc_whoami_image"></a> [lxc\_whoami\_image](#input\_lxc\_whoami\_image) | OCI image whose whoami binary (Entrypoint /whoami) is EXTRACTED with crane and run raw inside LXC containers — no docker-in-LXC. Default is the OTel-instrumented fork (ghcr.io/zalbiraw/whoami), so the LXC leg emits OTLP like the QEMU/k8s whoami and shows as its own service-graph node. Set to "" to fall back to the upstream traefik/whoami release binary (lxc\_whoami\_version), which has no tracing. | `string` | `"ghcr.io/zalbiraw/whoami:latest"` | no |
| <a name="input_lxc_whoami_version"></a> [lxc\_whoami\_version](#input\_lxc\_whoami\_version) | traefik/whoami RELEASE tag whose linux\_amd64 binary is installed inside LXC containers ONLY when lxc\_whoami\_image is "" (the upstream binary fallback — no OTLP tracing). | `string` | `"v1.11.0"` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB per whoami guest (VMs and containers) | `number` | `1024` | no |
| <a name="input_node_ssh"></a> [node\_ssh](#input\_node\_ssh) | SSH access to the Proxmox NODE, used to `pct push`/`pct exec` the whoami install into LXC containers (LXC has no cloud-init user-data path). Required when any app has type = "lxc"; null otherwise. | <pre>object({<br/>    host        = string<br/>    user        = optional(string, "root")<br/>    private_key = string<br/>  })</pre> | `null` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count per whoami guest (VMs and containers) | `number` | `1` | no |
| <a name="input_snippet_datastore_id"></a> [snippet\_datastore\_id](#input\_snippet\_datastore\_id) | Datastore the cloud-init user-data snippets are uploaded to (Snippets content type must be enabled; uploads ride the provider's SSH access) | `string` | `"local"` | no |
| <a name="input_template_name"></a> [template\_name](#input\_template\_name) | Name of the template QEMU apps clone (resolved to a VMID on the node). Takes precedence over template\_vm\_id. | `string` | `""` | no |
| <a name="input_template_vm_id"></a> [template\_vm\_id](#input\_template\_vm\_id) | VMID of the template QEMU apps clone. Provide this OR template\_name (only needed when at least one app has type = "vm"). Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template with qemu-guest-agent — the agent is what reports guest IPs, both to terraform and to the native discovery provider. | `number` | `0` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image docker-run on each VM (type = "vm"). LXC apps run the binary EXTRACTED from lxc\_whoami\_image instead (no docker in the container). Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/zalbiraw/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all whoami guests with their details. For type=vm, private\_ip is the QEMU-agent-reported guest IP; for type=lxc it is NULL — a container has no guest agent, so its DHCP lease is invisible to terraform. That is not a gap to work around: the native proxmox provider discovers container IPs itself via the PVE API, which is how the LXC legs get routed. No public-IP concept on-prem. |
<!-- END_TF_DOCS -->