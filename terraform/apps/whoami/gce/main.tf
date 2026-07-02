# whoami on GCE VMs — the GCP sibling of apps/whoami/ec2 and apps/whoami/azure-vm.
# Reuses the whoami/cloud-init template (docker-run systemd unit).
#
# UNLIKE EC2/Azure, the workload config is NOT tags: GCE metadata keys can't
# contain dots, so the Traefik Hub gce provider reads ONE metadata item with
# key `traefik` whose VALUE is a JSON object of Traefik labels. Each app's
# `traefik_labels` map is jsonencode()d into that item. GCE *labels* (dotless)
# feed provider constraints only.

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
        key            = "${app_name}-${replica_idx + 1}"
        app_name       = app_name
        traefik_labels = try(app_config.traefik_labels, {})
        labels         = try(app_config.labels, {})
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }

  app_ports = distinct([for app_name, app_config in var.apps : tostring(try(app_config.port, 80))])
}

resource "google_compute_instance" "whoami" {
  for_each = local.instances_map

  name         = each.key
  machine_type = var.machine_type
  zone         = var.zone
  # Network tags (dotless, firewall targeting only) — NOT the provider's
  # workload config; that's the `traefik` metadata item below.
  tags = var.network_tags

  boot_disk {
    initialize_params {
      image = var.vm_image
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork != "" ? var.subnetwork : null

    # An access_config block (even empty) allocates an ephemeral public IP.
    dynamic "access_config" {
      for_each = var.enable_public_ip ? [1] : []
      content {}
    }
  }

  metadata = merge(
    { user-data = module.cloud_init[each.value.app_name].rendered },
    # The gce provider's workload config: one `traefik` metadata item whose
    # value is a JSON object of dotted Traefik labels.
    length(each.value.traefik_labels) > 0 ? { traefik = jsonencode(each.value.traefik_labels) } : {}
  )

  # GCE labels (lowercase, dotless) — matched by the provider's `constraints`
  # expression only; they carry no traefik.* routing config.
  labels = merge(var.common_labels, each.value.labels)
}

# Open the app ports intra-network (mirrors compute/azure/vnet's NSG idea —
# GCP firewalls are VPC-scoped, so the rule lives with the instances it targets).
resource "google_compute_firewall" "whoami" {
  count = var.enable_firewall ? 1 : 0

  name    = "allow-${var.network_tags[0]}"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = local.app_ports
  }

  source_ranges = var.firewall_source_ranges
  target_tags   = var.network_tags
}
