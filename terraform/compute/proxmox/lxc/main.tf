# =============================================================================
# compute/proxmox/lxc — the shared LXC container primitive
# =============================================================================
# Extracted verbatim from traefik/proxmox-lxc and apps/whoami/proxmox, which
# created the identical proxmox_virtual_environment_container. An unprivileged,
# nesting-enabled container (systemd inside). Addressing is per-instance: DHCP
# (whoami backends, discovered via the PVE API) or a static CIDR + gateway + dns
# (the gateway child, whose :9443 uplink the hub dials at a plan-known address).
#
# The in-container install (pct push + pct exec over SSH to the node) is role
# config and stays in the callers; they read the container id from `instances`.
# =============================================================================

resource "proxmox_virtual_environment_container" "this" {
  for_each = var.instances

  node_name = var.node_name

  description = each.value.description

  unprivileged = true

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  cpu {
    cores = var.num_cpus
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = each.value.gateway
      }
    }

    dynamic "dns" {
      for_each = each.value.dns != null ? [each.value.dns] : []
      content {
        servers = dns.value.servers
        domain  = dns.value.domain
      }
    }
  }

  features {
    nesting = true # systemd inside an unprivileged container
  }

  started = true
}

locals {
  # Static (non-DHCP) instances expose their pinned IP (minus the /prefix) —
  # known at plan time. DHCP containers report null: a container has no guest
  # agent, so its lease is invisible to terraform (the proxmox plugin discovers
  # those IPs itself via the PVE API).
  private_ips = {
    for key, inst in var.instances : key =>
    inst.ip_address != "dhcp" && inst.ip_address != "" ? split("/", inst.ip_address)[0] : null
  }
}
