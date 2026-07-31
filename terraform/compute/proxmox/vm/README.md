# compute/proxmox/vm

The shared **QEMU VM primitive** on Proxmox VE. Clones a cloud-init-enabled Ubuntu cloud-image template, uploads the caller-rendered user-data as a PVE **snippet file** (`content_type = "snippets"`, hash-named so a content change `replace_triggered_by`s the VM), and boots the VM with the QEMU guest agent enabled so its guest IP is reported back.

Both `traefik/proxmox-vm` (one gateway VM) and `apps/whoami/proxmox` (N whoami VMs) compose this module — the resource that used to be duplicated in both. It owns **no role config**: `user_data` (the rendered cloud-init) and the guest `description` arrive as opaque per-instance strings.

## Example usage

```hcl
module "vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/proxmox/vm?ref=v5.2.0"

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
<!-- END_TF_DOCS -->
