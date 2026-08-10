# apps/whoami/vsphere

Provisions one or more Traefik `whoami` instances on vSphere VMs — the on-prem sibling of `apps/whoami/ec2` / `apps/whoami/azure-vm` / `apps/whoami/gce`, reusing the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`). Each replica is one small VM cloned from a user-provided **cloud-init-enabled Ubuntu cloud-image template**.

## The workload config is guestinfo JSON, not tags

vSphere tags and custom attributes must be **registered centrally** (in vCenter) before they can be attached to a VM — too heavy for free-form config. The Traefik Hub `vsphere` provider therefore reads **one extraConfig entry with key `guestinfo.traefik` whose value is a JSON object of Traefik labels** (the same JSON-blob story as GCE's `traefik` metadata item):

```json
{"traefik.enable": "true", "traefik.http.services.whoami.loadbalancer.server.port": "80"}
```

This module takes a `traefik_labels` map per app (dotted label → value) and `jsonencode()`s it into that entry. The provider's `constraints` expression matches **those same labels plus a synthesized `name` pseudo-label** (the VM name) — there is no separate label system. Note the provider does **no port discovery** (vSphere has no per-VM firewall primitive to read), so the `server.port` label is required.

## Example usage

```hcl
module "whoami_vsphere" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/vsphere?ref=v6.1.0"

  datacenter = "dc-01"
  datastore  = "datastore-01"
  cluster    = "cluster-01"
  network    = "VM Network"
  template   = "ubuntu-24.04-cloudimg"

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-vsphere" # body shows `Name: whoami-vsphere`
      traefik_labels = {
        "traefik.enable"                                        = "true"
        "traefik.http.services.whoami.loadbalancer.server.port" = "80" # REQUIRED — no port discovery
      }
    }
  }
}
```

## Prerequisites

- vCenter credentials allowed to clone VMs; DHCP on the target network.
- A **cloud-init-enabled Ubuntu cloud-image template** (see `compute/vsphere/k3s`'s README for the import recipe). The cloud images ship `open-vm-tools`, which is what reports the guest IP — both this module's `instances` output and the vsphere provider's discovery depend on it.

## Notes

- The `instances` output exposes each VM's `private_ip` (its `default_ip_address`) — the Traefik child dials these in-network; the provider's `private` and `public` ipModes both resolve to this same primary guest address (no cloud public-IP concept).
- Per-VM ipMode override: the `traefik.vsphere.ipmode` label.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |

## Providers

No providers.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_datacenter"></a> [datacenter](#input\_datacenter) | Name of the vSphere datacenter the VMs are created in | `string` | n/a | yes |
| <a name="input_datastore"></a> [datastore](#input\_datastore) | Name of the datastore backing the VMs' disks | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Name of the port group / network the VM NICs join (DHCP is assumed; the Traefik child dials each VM's guest IP) | `string` | n/a | yes |
| <a name="input_template"></a> [template](#input\_template) | Name of the VM template to clone. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (e.g. imported from ubuntu-24.04-server-cloudimg-amd64.ova) — a plain installer-built template ignores the guestinfo userdata and whoami never starts. | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to vSphere VMs. Each app can have multiple replicas. { name = { replicas, port, name, environment, services } } — `services` is a list of vCenter TAG names (in var.service\_tag\_category) naming the Traefik services these VMs back; each VM is attached to every one, which is how the Hub vsphere provider discovers them. Optional `environment` (map) is merged over the module-level `environment` into the container. `traefik_labels` is accepted but INERT: the vCenter-native provider reads tags, not per-VM labels. | `any` | `{}` | no |
| <a name="input_cluster"></a> [cluster](#input\_cluster) | Name of the compute cluster to place the VMs in (its root resource pool). Provide this OR resource\_pool. | `string` | `""` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Disk size in GB. Grown to at least the template's disk (vSphere can't shrink on clone). | `number` | `20` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_folder"></a> [folder](#input\_folder) | VM folder to place the VMs in. Empty = the datacenter root. | `string` | `""` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB per whoami VM | `number` | `1024` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count per whoami VM | `number` | `1` | no |
| <a name="input_resource_pool"></a> [resource\_pool](#input\_resource\_pool) | Name/path of the resource pool to place the VMs in. Takes precedence over cluster. | `string` | `""` | no |
| <a name="input_service_tag_ids"></a> [service\_tag\_ids](#input\_service\_tag\_ids) | vCenter tag NAME -> tag ID, covering every name used in the apps' `services` lists. Passed in because the caller owns the category and tags; looking them up here would fail on a first apply, when they do not exist yet. The category itself never reaches this module — IDs are globally unique, so attaching a tag needs no category name. | `map(string)` | `{}` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each VM. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server VMs with their details (private\_ip is the guest IP reported by open-vm-tools — vSphere VMs have one primary address, no cloud public-IP concept) |
<!-- END_TF_DOCS -->