# metal — an on-demand phoenixNAP Bare Metal Cloud server, billed HOURLY by default.
#
# This is the layer BELOW the private-cloud demos: the proxmox/vsphere/morpheus
# demos run against a hypervisor that must already exist somewhere
# (compute/{proxmox,vsphere,morpheus}/k3s attach to one — they don't create it).
# This module provisions that host natively on rented metal, imaged per demo via
# `os` — BMC images all three bases directly (no nesting):
#   proxmox/proxmox9  -> the Proxmox demo's PVE node
#   esxi/esxi80       -> the vSphere demo's ESXi host (60-day eval; deploy VCSA on top)
#   ubuntu/noble      -> the Morpheus demo's HVM base (install the hpe-vm stack)
# Changing `os` replaces the server — that IS the workflow: provision for a demo,
# test, destroy (hourly billing stops) or re-apply with the next os.
#
# The pnap provider authenticates from ~/.pnap/config.yaml (client_id/client_secret
# from the BMC portal) — the OPERATOR's credential, configured in the demo root,
# never here.

resource "pnap_server" "metal" {
  hostname    = var.hostname
  description = var.description

  os       = var.os
  type     = var.type
  location = var.location

  # SSH keys are the only day-one access for the Linux images (proxmox/ubuntu);
  # the ESXi image is reached with the generated root password (see outputs).
  ssh_keys                 = var.ssh_keys
  install_default_ssh_keys = var.install_default_ssh_keys

  # Scope the management UI (Proxmox :8006, etc.) to these IPs at the BMC network
  # layer — the native 'White Listed IPs' control, set at provision time.
  management_access_allowed_ips = var.management_access_allowed_ips

  pricing_model = var.pricing_model
  network_type  = var.network_type

  # Take the auto-allocated public IP block down WITH the server. Without this BMC keeps
  # the block after `terraform destroy`: it is no longer in state, no longer attached to
  # anything, and still billed — the demos leaked 17 of them before this was set.
  delete_ip_blocks = var.delete_ip_blocks

  # Attach a caller-supplied block when the guests need public addresses too (see
  # var.ip_block_id). Omitted -> BMC allocates its default /30 for the host alone.
  dynamic "network_configuration" {
    for_each = var.ip_block_id == null ? [] : [var.ip_block_id]
    content {
      ip_blocks_configuration {
        configuration_type = "USER_DEFINED"
        ip_blocks {
          server_ip_block {
            id = network_configuration.value
          }
        }
      }
    }
  }

  lifecycle {
    # DO NOT REMOVE. management_access_allowed_ips is PROVISION-TIME ONLY: the
    # provider has no in-place update path, so any diff on it REPLACES the server —
    # i.e. re-images the live box and destroys the lab on top of it.
    #
    # Callers typically feed this from the operator's current public IP (the
    # private-cloud demos use a live `data.http` lookup), which changes with a VPN,
    # a new DHCP lease, or a different network. Without this guard, simply applying
    # from a coffee shop silently wipes the box — and the demos run
    # `terraform apply -auto-approve`, so the replacement never surfaces for review.
    #
    # Ignoring it means the whitelist is fixed at CREATE. To re-scope it, change the
    # value and `-replace` the server deliberately (it is a re-image either way).
    ignore_changes = [management_access_allowed_ips]
  }
}
