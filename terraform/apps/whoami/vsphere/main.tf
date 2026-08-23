# whoami on vSphere VMs — the on-prem sibling of apps/whoami/ec2 /
# apps/whoami/azure-vm / apps/whoami/gce. Clones a cloud-init-enabled Ubuntu
# cloud-image template and reuses the whoami/cloud-init template (docker-run
# systemd unit).
#
# The workload config is the VM's NOTES (config.annotation): the Traefik Hub
# vsphere provider reads a LINE-FORMAT label block from it — one
# `traefik.<key>=<value>` per line, the same grammar the proxmox and hyperv
# siblings put in their guest descriptions. Each app's `traefik_labels` map is
# rendered into that block. The provider MERGES same-named services across VMs,
# so N replicas carrying one identical block become one N-server service — which
# is how one fleet is published under several load-balancing strategies.

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

  # The native vsphere provider reads LINE-FORMAT labels from the VM Notes
  # (extractTraefikAnnotation parses one `traefik.<key>=<value>` per line; blank
  # lines and a leading `# comment` are tolerated). Render the dotted label map
  # into that block — the same renderer as the proxmox/hyperv/kubevirt siblings,
  # deliberately duplicated rather than shared.
  descriptions = {
    for k, inst in local.instances_map :
    k => join("\n", [for lk, lv in inst.traefik_labels : "${lk}=${lv}"])
  }
}

# N workload VMs cloned from the shared compute/vsphere/vm module. This caller
# still renders the whoami cloud-init (per app, via module.cloud_init) and the
# provider's label block (traefik_labels -> Notes); the module owns the
# vsphere_virtual_machine resource and its data lookups.
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

  # The provider's label block in each VM's Notes — left untouched when an app
  # carries no labels.
  annotation = {
    for key, inst in local.instances_map : key => local.descriptions[key] if length(inst.traefik_labels) > 0
  }

  # Static addressing at boot, when the caller wants one (no DHCP on the network, or an
  # address that must be known at plan time). Keyed by instance key, like user_data.
  network_config = var.network_config
}
