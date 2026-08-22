# compute/vsphere/vm

Shared **vSphere VM fleet** — the single infra module behind both `traefik/vsphere-vm` (one gateway VM) and `apps/whoami/vsphere` (N workload VMs). Clones a cloud-init-enabled Ubuntu cloud-image template into one `vsphere_virtual_machine` per instance key (`<app>-<replica>`), and owns the datacenter/datastore/cluster/resource_pool/network/template data lookups.

Role-agnostic by design: cloud-init is rendered by the caller and passed in as opaque `user_data`; the vsphere provider's workload config (the `guestinfo.traefik` entry) is built by the caller and passed in as opaque `extra_config` guestinfo entries. Outputs mirror the other `compute/*` modules (`instances` / `private_ips` / `public_ips`) — on vSphere both IP maps carry the same primary guest address.

## Example usage

```hcl
module "vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/vsphere/vm?ref=v6.5.0"

  datacenter = "dc-01"
  datastore  = "datastore-01"
  cluster    = "cluster-01"
  network    = "VM Network"
  template   = "ubuntu-24.04-cloudimg"

  apps = {
    whoami = { replicas = 2 }
  }

  user_data = {
    "whoami-1" = local.rendered_cloud_init
    "whoami-2" = local.rendered_cloud_init
  }

  extra_config = {
    "whoami-1" = { "guestinfo.traefik" = jsonencode(local.traefik_labels) }
    "whoami-2" = { "guestinfo.traefik" = jsonencode(local.traefik_labels) }
  }
}
```

## Prerequisites

- vCenter credentials allowed to clone VMs; DHCP on the target network.
- A **cloud-init-enabled Ubuntu cloud-image template** (see `compute/vsphere/k3s`'s README for the import recipe). The cloud images ship `open-vm-tools`, which reports the guest IP the `instances` output and the vsphere provider's discovery both depend on.
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_vsphere"></a> [vsphere](#requirement\_vsphere) | ~> 2.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_vsphere"></a> [vsphere](#provider\_vsphere) | ~> 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [vsphere_virtual_machine.vm](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/resources/virtual_machine) | resource |
| [vsphere_compute_cluster.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/compute_cluster) | data source |
| [vsphere_datacenter.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/datacenter) | data source |
| [vsphere_datastore.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/datastore) | data source |
| [vsphere_network.extra](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/network) | data source |
| [vsphere_network.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/network) | data source |
| [vsphere_resource_pool.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/resource_pool) | data source |
| [vsphere_virtual_machine.template](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/virtual_machine) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_datacenter"></a> [datacenter](#input\_datacenter) | Name of the vSphere datacenter the VMs are created in | `string` | n/a | yes |
| <a name="input_datastore"></a> [datastore](#input\_datastore) | Name of the datastore backing the VMs' disks | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Name of the port group / network the VM NICs join (DHCP is assumed; the Traefik child dials each VM's guest IP) | `string` | n/a | yes |
| <a name="input_template"></a> [template](#input\_template) | Name of the VM template to clone. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (e.g. imported from ubuntu-24.04-server-cloudimg-amd64.ova) — a plain installer-built template ignores the guestinfo userdata and the workload never starts. | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of apps to expand into VMs. Each app yields `replicas` VMs keyed `<app>-<replica>` (mirrors compute/aws/ec2). The gateway calls with one app/replica; whoami with N. `user_data` and `extra_config` are keyed by those same instance keys. | <pre>map(object({<br/>    replicas = optional(number, 1)<br/>  }))</pre> | `{}` | no |
| <a name="input_cluster"></a> [cluster](#input\_cluster) | Name of the compute cluster to place the VMs in (its root resource pool). Provide this OR resource\_pool. | `string` | `""` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Disk size in GB. Grown to at least the template's disk (vSphere can't shrink on clone). | `number` | `20` | no |
| <a name="input_extra_config"></a> [extra\_config](#input\_extra\_config) | Extra guestinfo extraConfig entries merged onto each VM, keyed by instance key. The caller builds the vsphere provider's workload config here — e.g. { "<app>-1" = { "guestinfo.traefik" = jsonencode(labels) } }. Empty per-key map adds nothing. | `map(map(string))` | `{}` | no |
| <a name="input_extra_networks"></a> [extra\_networks](#input\_extra\_networks) | Additional portgroups to attach, in order, after var.network. Used for multi-homed VMs — the demo's router VM sits on the public VLAN and the internal one. Guest interface names follow the attach order (ens192, ens224, ...). | `list(string)` | `[]` | no |
| <a name="input_folder"></a> [folder](#input\_folder) | VM folder to place the VMs in. Empty = the datacenter root. | `string` | `""` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB per VM | `number` | `4096` | no |
| <a name="input_network_config"></a> [network\_config](#input\_network\_config) | Per-instance cloud-init network-config v2, keyed by instance key. Merged into the guestinfo metadata, so it is applied at BOOT — before cloud-init installs packages or runs commands. That ordering is the point: a VM on a network without DHCP has no connectivity during the package stage, and anything configured later (a netplan file written by write\_files, applied in runcmd) comes far too late to save the apt run. Empty = DHCP. | `any` | `{}` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count per VM | `number` | `2` | no |
| <a name="input_replica_start_index"></a> [replica\_start\_index](#input\_replica\_start\_index) | Starting index for replica numbering (Default: 1). Instance keys are `<app>-<replica_idx + replica_start_index>`. | `number` | `1` | no |
| <a name="input_resource_pool"></a> [resource\_pool](#input\_resource\_pool) | Name/path of the resource pool to place the VMs in. Takes precedence over cluster. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | vCenter tag IDs to attach, keyed by instance key. The vsphere provider has no standalone attach resource — tags ride the VM resource itself, so they are set at create. Used to declare which Traefik services a VM backs (the Hub vsphere provider discovers by tag). | `map(list(string))` | `{}` | no |
| <a name="input_user_data"></a> [user\_data](#input\_user\_data) | Rendered cloud-init user-data per instance, keyed by instance key (`<app>-<replica>`). base64-encoded into the VM's `guestinfo.userdata` extraConfig entry. Opaque to this module — the caller renders it. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all VMs with their details (private\_ip and public\_ip are the SAME guest address reported by open-vm-tools — vSphere VMs have one primary IP and no cloud public-IP concept). |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance keys to their guest IP addresses. |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance keys to their guest IP addresses — identical to private\_ips (no public-IP concept on vSphere; kept for sibling-parity). |
<!-- END_TF_DOCS -->
