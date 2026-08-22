# compute/proxmox/vm

The shared **QEMU VM primitive** on Proxmox VE. Clones a cloud-init-enabled Ubuntu cloud-image template, uploads the caller-rendered user-data as a PVE **snippet file** (`content_type = "snippets"`, hash-named so a content change `replace_triggered_by`s the VM), and boots the VM with the QEMU guest agent enabled so its guest IP is reported back.

Both `traefik/proxmox-vm` (one gateway VM) and `apps/whoami/proxmox` (N whoami VMs) compose this module — the resource that used to be duplicated in both. It owns **no role config**: `user_data` (the rendered cloud-init) and the guest `description` arrive as opaque per-instance strings.

## Example usage

```hcl
module "vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/proxmox/vm?ref=v6.7.0"

  node_name     = "pve"
  datastore_id  = "local-lvm"
  template_name = "ubuntu-24.04-cloudimg" # or template_vm_id = 9000

  instances = {
    "traefik-1" = {
      user_data   = local.rendered_cloud_init
      description = "traefik.enable=true"
    }
  }
}
```

## Prerequisites

- A `bpg/proxmox` provider configured with an `ssh {}` block (snippet uploads go over SSH/SFTP; the PVE API has no snippet upload).
- The snippet datastore must allow the Snippets content type (`snippet_datastore_id`, default `local`).
- The clone template must be a cloud-init-enabled Ubuntu cloud image shipping `qemu-guest-agent`.
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
| [proxmox_virtual_environment_file.user_data](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_vm.this](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |
| [proxmox_virtual_environment_vms.template](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/data-sources/virtual_environment_vms) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Datastore backing the VMs' disks and cloud-init drives (e.g. local-lvm) | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Name of the Proxmox VE node the VMs are created on | `string` | n/a | yes |
| <a name="input_bridge"></a> [bridge](#input\_bridge) | Name of the Linux bridge each VM's NIC joins (DHCP is assumed; the parent dials the guest IP the QEMU agent reports) | `string` | `"vmbr0"` | no |
| <a name="input_cpu_type"></a> [cpu\_type](#input\_cpu\_type) | QEMU CPU type. `host` passes the node's CPU through; pick a named model when live migration matters. | `string` | `"host"` | no |
| <a name="input_disk_interface"></a> [disk\_interface](#input\_disk\_interface) | Interface of the template's disk to resize (the standard cloud-image import recipe attaches it as scsi0) | `string` | `"scsi0"` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Disk size in GB. Must be at least the template's disk (Proxmox can't shrink on clone). | `number` | `20` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | Map of VMs to create, keyed by VM name (used as the VM's `name` and the snippet file name stem). user\_data is the already-rendered cloud-init snippet (opaque); description is the guest Notes/description (null = unset). | <pre>map(object({<br/>    user_data   = string<br/>    description = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB per VM | `number` | `4096` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count per VM | `number` | `2` | no |
| <a name="input_snippet_datastore_id"></a> [snippet\_datastore\_id](#input\_snippet\_datastore\_id) | Datastore the cloud-init user-data snippets are uploaded to (Snippets content type must be enabled; uploads ride the bpg provider's SSH access) | `string` | `"local"` | no |
| <a name="input_snippet_name_prefix"></a> [snippet\_name\_prefix](#input\_snippet\_name\_prefix) | Prefix prepended to each snippet's file name (before the instance key and content hash). traefik/proxmox-vm passes "" (files are `<key>-<hash>.cloud-config.yaml`); apps/whoami/proxmox passes "whoami-". | `string` | `""` | no |
| <a name="input_template_name"></a> [template\_name](#input\_template\_name) | Name of the template to clone (resolved to a VMID on the node). Takes precedence over template\_vm\_id. | `string` | `""` | no |
| <a name="input_template_vm_id"></a> [template\_vm\_id](#input\_template\_vm\_id) | VMID of the template to clone. Provide this OR template\_name. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template with qemu-guest-agent (the agent reports the guest IP). | `number` | `0` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the created VMs with their details (keyed by VM name). private\_ip and public\_ip are the SAME guest address — Proxmox guests have one primary IP and no cloud public-IP concept. |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their QEMU-agent-reported guest IP addresses |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their guest IP addresses — identical to private\_ips (no public-IP concept on Proxmox; kept for sibling-parity) |
<!-- END_TF_DOCS -->
