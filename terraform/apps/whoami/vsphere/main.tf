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
        services       = try(app_config.services, [])
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }
}

# N workload VMs cloned from the shared compute/vsphere/vm module. This caller
# still renders the whoami cloud-init (per app, via module.cloud_init) and
# builds the vsphere provider's workload config (traefik_labels ->
# guestinfo.traefik); the module owns the vsphere_virtual_machine resource and
# its data lookups.
module "compute" {
  source = "../../../compute/vsphere/vm"

  datacenter    = var.datacenter
  datastore     = var.datastore
  cluster       = var.cluster
  resource_pool = var.resource_pool
  network       = var.network
  template      = var.template
  folder        = var.folder

  num_cpus  = var.num_cpus
  memory    = var.memory
  disk_size = var.disk_size

  apps = {
    for app_name, app_config in var.apps : app_name => { replicas = app_config.replicas }
  }

  # Per-app cloud-init, mapped onto each replica's instance key.
  user_data = {
    for key, inst in local.instances_map : key => module.cloud_init[inst.app_name].rendered
  }

  # The vsphere provider's `guestinfo.traefik` entry per instance — omitted when
  # an app carries no labels, exactly as before.
  extra_config = {
    for key, inst in local.instances_map : key => length(inst.traefik_labels) > 0 ? { "guestinfo.traefik" = jsonencode(inst.traefik_labels) } : {}
  }

  # vCenter tags naming the services each VM backs — how the Hub vsphere provider
  # discovers them (see the tag block below).
  tags = local.instance_tag_ids
}

# --- vCenter tags: which SERVICES each VM backs -----------------------------------
# The vCenter-native Traefik Hub provider reads service membership from tags, not from
# per-VM labels: a VM tagged `vmrr` in the service-name category is a server of the
# `vmrr` service. The category must be MULTIPLE-cardinality, which is what lets one VM
# carry several tags and so appear in several services — the same fleet published under
# wrr, leasttime and hrw, which is the whole point of the load-balancing acts.
#
# The category and tags are looked up, not created: they are demo-wide (and the category's
# cardinality matters), so the caller owns them.
data "vsphere_tag_category" "traefik_service" {
  count = length(local.service_tag_pairs) > 0 ? 1 : 0
  name  = var.service_tag_category
}

data "vsphere_tag" "service" {
  for_each = toset(flatten([for inst in local.instances : inst.services]))

  name        = each.value
  category_id = data.vsphere_tag_category.traefik_service[0].id
}

locals {
  # One (vm, service) pair per tag to attach.
  service_tag_pairs = flatten([
    for key, inst in local.instances_map : [
      for svc in inst.services : { key = key, service = svc }
    ]
  ])
}

locals {
  # instance key -> the tag ids that VM carries. Attached through the VM resource's own
  # `tags` argument (the vsphere provider has no separate attach resource), so tagging is
  # part of creating the VM rather than a second-pass association.
  instance_tag_ids = {
    for key, inst in local.instances_map :
    key => [for svc in inst.services : data.vsphere_tag.service[svc].id]
  }
}
