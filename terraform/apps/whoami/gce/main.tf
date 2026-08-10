# whoami on GCE VMs — the GCP sibling of apps/whoami/ec2 and apps/whoami/azure-vm.
# Reuses the whoami/cloud-init template (docker-run systemd unit).
#
# UNLIKE EC2/Azure, the workload config is NOT dotted tags: a GCE VM carries
# ONLY a service name, as the value of a plain GCE label (the Hub gce
# provider's serviceNameLabel, default `traefik-service`). Set it via each
# app's `labels` map. GCE label values are lowercase [a-z0-9_-] and
# single-valued — one VM backs one service. All routing intent (routers,
# services, strategies) lives in the base configuration the gateway's gce
# provider loads (configEndpoint/filename), never on the VM.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-gce).
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

locals {
  # Replicate the ec2/azure-vm siblings' instance-key scheme: "<app>-<replica>".
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key      = "${app_name}-${replica_idx + 1}"
        app_name = app_name
        labels   = try(app_config.labels, {})
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }

  app_ports = distinct([for app_name, app_config in var.apps : tostring(try(app_config.port, 80))])
}

# The VMs (and their firewall) live in the shared compute/gcp/vm module. This
# caller keeps everything role-specific: the rendered cloud-init and the GCE
# labels — including the service-name label (e.g. `traefik-service: <name>`)
# that is the ONLY workload config a VM carries under the gce provider's
# contract. The compute module just materializes the instances.
module "compute" {
  source = "../../../compute/gcp/vm"

  instances = {
    for key, inst in local.instances_map : key => {
      metadata = { user-data = module.cloud_init[inst.app_name].rendered }
      # GCE labels (lowercase [a-z0-9_-], single-valued). The service-name
      # label's value names the ONE service this VM backs; everything else
      # about that service lives in the gateway's base configuration.
      labels = merge(var.common_labels, inst.labels)
    }
  }

  machine_type     = var.machine_type
  zone             = var.zone
  vm_image         = var.vm_image
  network          = var.network
  subnetwork       = var.subnetwork
  enable_public_ip = var.enable_public_ip
  # Network tags (dotless, firewall targeting only) — NOT the provider's
  # workload config; that's the `traefik` metadata item above.
  tags = var.network_tags

  # Open the app ports intra-network (mirrors compute/azure/vnet's NSG idea —
  # GCP firewalls are VPC-scoped, so the rule lives with the instances it targets).
  enable_firewall        = var.enable_firewall
  firewall_ports         = local.app_ports
  firewall_source_ranges = var.firewall_source_ranges
}
