# whoami on vSphere VMs — the on-prem sibling of apps/whoami/ec2 /
# apps/whoami/azure-vm / apps/whoami/gce. Clones a cloud-init-enabled Ubuntu
# cloud-image template and reuses the whoami/cloud-init template (docker-run
# systemd unit).
#
# LIKE GCE (and unlike EC2/Azure tags), the workload config is NOT tags:
# vSphere tags must be registered centrally before use, so the Traefik Hub
# vsphere provider reads ONE extraConfig entry with key `guestinfo.traefik`
# whose VALUE is a JSON object of Traefik labels. Each app's `traefik_labels`
# map is jsonencode()d into that entry. The provider's `constraints` match
# those same labels plus a synthesized `name` pseudo-label (the VM name) —
# there is no separate label system.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-vsphere).
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

locals {
  # Replicate the ec2/azure-vm/gce siblings' instance-key scheme: "<app>-<replica>".
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key            = "${app_name}-${replica_idx + 1}"
        app_name       = app_name
        traefik_labels = try(app_config.traefik_labels, {})
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

data "vsphere_virtual_machine" "template" {
  name          = var.template
  datacenter_id = data.vsphere_datacenter.this.id
}

locals {
  resource_pool_id = var.resource_pool != "" ? data.vsphere_resource_pool.this[0].id : data.vsphere_compute_cluster.this[0].resource_pool_id
}

resource "vsphere_virtual_machine" "whoami" {
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

  extra_config = merge(
    {
      "guestinfo.userdata"          = base64encode(module.cloud_init[each.value.app_name].rendered)
      "guestinfo.userdata.encoding" = "base64"
      "guestinfo.metadata"          = base64encode(jsonencode({ "instance-id" = each.key, "local-hostname" = each.key }))
      "guestinfo.metadata.encoding" = "base64"
    },
    # The vsphere provider's workload config: one `guestinfo.traefik` entry
    # whose value is a JSON object of dotted Traefik labels.
    length(each.value.traefik_labels) > 0 ? { "guestinfo.traefik" = jsonencode(each.value.traefik_labels) } : {}
  )

  # The `instances` output reads default_ip_address, reported by open-vm-tools
  # (the Ubuntu cloud images ship it) — also what gates the provider's
  # discovery: no tools, no guest IP, no route.
  wait_for_guest_net_timeout = 10
}
