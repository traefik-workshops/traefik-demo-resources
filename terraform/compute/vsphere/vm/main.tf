# =============================================================================
# compute/vsphere/vm — the shared vSphere VM fleet
# =============================================================================
# Clones a cloud-init-enabled Ubuntu cloud-image template into one VM per
# instance key. Cloud-init (`user_data`) and the vsphere provider's workload
# config (`extra_config`, e.g. the `guestinfo.traefik` entry) are rendered by
# the CALLER and handed in as opaque maps keyed by instance key — this module
# holds nothing role-specific. Both traefik/vsphere-vm and apps/whoami/vsphere
# compose it.
# =============================================================================

locals {
  # Expand apps × replicas into per-VM instance keys "<app>-<replica>", matching
  # the ec2/azure-vm/gce siblings (and compute/aws/ec2).
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key      = "${app_name}-${replica_idx + var.replica_start_index}"
        app_name = app_name
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }
}

data "vsphere_datacenter" "this" {
  name = var.datacenter
}

data "vsphere_datastore" "this" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_compute_cluster" "this" {
  count         = var.resource_pool == "" ? 1 : 0
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_resource_pool" "this" {
  count         = var.resource_pool != "" ? 1 : 0
  name          = var.resource_pool
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_network" "this" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_network" "extra" {
  for_each = toset(var.extra_networks)

  name          = each.value
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template
  datacenter_id = data.vsphere_datacenter.this.id
}

locals {
  resource_pool_id = var.resource_pool != "" ? data.vsphere_resource_pool.this[0].id : data.vsphere_compute_cluster.this[0].resource_pool_id
}

resource "vsphere_virtual_machine" "vm" {
  for_each = local.instances_map

  name             = each.key
  resource_pool_id = local.resource_pool_id
  datastore_id     = data.vsphere_datastore.this.id
  folder           = var.folder != "" ? var.folder : null

  num_cpus = var.num_cpus
  memory   = var.memory

  # Inherit the template's hardware identity so the clone boots unchanged.
  guest_id  = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type
  firmware  = data.vsphere_virtual_machine.template.firmware

  network_interface {
    network_id   = data.vsphere_network.this.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  # Additional NICs, in declaration order — the guest names them ens192, ens224, ...
  dynamic "network_interface" {
    for_each = var.extra_networks
    content {
      network_id   = data.vsphere_network.extra[network_interface.value].id
      adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
    }
  }

  disk {
    label = "disk0"
    # Never below the template's disk — vSphere refuses to shrink on clone.
    size             = max(data.vsphere_virtual_machine.template.disks[0].size, var.disk_size)
    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks[0].eagerly_scrub
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  # A CLIENT cdrom, required whenever the template carries vApp properties with the
  # default `iso` OVF environment transport — which every stock cloud-image OVA does
  # (Ubuntu's ubuntu-24.04-server-cloudimg-amd64.ova included). Without it the plan fails
  # with "this virtual machine requires a client CDROM device to deliver vApp properties",
  # and adding the device to the TEMPLATE is not enough: vSphere wants it on the clone.
  #
  # Nothing is mounted in it. This module delivers cloud-init through the guestinfo keys
  # below, not through an OVF environment ISO; the device exists only to satisfy the
  # template's declared transport.
  cdrom {
    client_device = true
  }

  extra_config = merge(
    {
      "guestinfo.userdata"          = base64encode(var.user_data[each.key])
      "guestinfo.userdata.encoding" = "base64"
      "guestinfo.metadata" = base64encode(jsonencode(merge(
        { "instance-id" = each.key, "local-hostname" = each.key },
        # Network-config v2 when the caller supplies one — applied at boot, before the
        # package stage (see var.network_config). Absent = cloud-init's DHCP fallback.
        try(var.network_config[each.key], null) == null ? {} : { network = var.network_config[each.key] },
      )))
      "guestinfo.metadata.encoding" = "base64"
    },
    # The caller's workload config (e.g. the vsphere provider's `guestinfo.traefik`
    # entry). An empty per-key map merges nothing.
    try(var.extra_config[each.key], {})
  )

  # vCenter tags (ids) for this VM — e.g. the Traefik services it backs.
  tags = try(var.tags[each.key], [])

  # The `instances` output reads default_ip_address, reported by open-vm-tools
  # (the Ubuntu cloud images ship it) — also what gates the provider's
  # discovery: no tools, no guest IP, no route.
  wait_for_guest_net_timeout = 10
}
