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

  # Static addressing at boot, when the caller wants one (no DHCP on the network, or an
  # address that must be known at plan time). Keyed by instance key, like user_data.
  network_config = var.network_config
}

# --- vCenter tags: which SERVICES each VM backs -----------------------------------
# The vCenter-native Traefik Hub provider reads service membership from tags: a VM tagged
# `vmrr` is a server of the `vmrr` service, and a MULTIPLE-cardinality category lets one
# VM carry several tags and so back several services (the same fleet under three LB
# strategies — the whole point of the load-balancing acts).
#
# Tag IDs are passed IN rather than looked up here. The caller creates the category and
# tags, and a data-source lookup in the same apply cannot see resources that apply has
# not created yet ("category name ... not found").
locals {
  instance_tag_ids = {
    for key, inst in local.instances_map :
    key => [for svc in inst.services : var.service_tag_ids[svc]]
  }
}
