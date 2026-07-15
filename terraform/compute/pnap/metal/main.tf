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
}
