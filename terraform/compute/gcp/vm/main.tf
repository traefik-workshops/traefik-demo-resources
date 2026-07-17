resource "google_compute_instance" "vm" {
  for_each = var.instances

  name         = each.key
  machine_type = var.machine_type
  zone         = var.zone
  tags         = var.tags

  boot_disk {
    initialize_params {
      image = var.vm_image
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork != "" ? var.subnetwork : null
    network_ip = each.value.network_ip != "" ? each.value.network_ip : null

    # An access_config block (even empty) allocates an ephemeral public IP.
    dynamic "access_config" {
      for_each = var.enable_public_ip ? [1] : []
      content {}
    }
  }

  metadata = each.value.metadata

  labels = each.value.labels

  dynamic "service_account" {
    for_each = var.service_account != null ? [var.service_account] : []
    content {
      email  = service_account.value.email
      scopes = service_account.value.scopes
    }
  }
}

# Open the demo ports intra-network (mirrors compute/azure/vnet's NSG idea —
# GCP firewalls are VPC-scoped, so the rule lives with the VMs it targets).
resource "google_compute_firewall" "vm" {
  count = var.enable_firewall ? 1 : 0

  name    = "allow-${var.tags[0]}"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = var.firewall_ports
  }

  source_ranges = var.firewall_source_ranges
  target_tags   = var.tags
}
