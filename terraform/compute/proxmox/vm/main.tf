# =============================================================================
# compute/proxmox/vm — the shared QEMU VM primitive
# =============================================================================
# Extracted verbatim from traefik/proxmox-vm and apps/whoami/proxmox, which
# created the identical proxmox_virtual_environment_file (snippet) +
# proxmox_virtual_environment_vm pair. The cloud-config snippet is hash-named
# into its file name with replace_triggered_by so a user-data change replaces
# the file AND the VM (cloud-init runs on first boot only) — that mechanism is
# infra and lives here.
# =============================================================================

# Resolve template_name -> VMID when the template is given by name.
data "proxmox_virtual_environment_vms" "template" {
  count     = var.template_name != "" ? 1 : 0
  node_name = var.node_name

  filter {
    name   = "name"
    values = [var.template_name]
  }
}

locals {
  template_vm_id = var.template_name != "" ? data.proxmox_virtual_environment_vms.template[0].vms[0].vm_id : var.template_vm_id
}

# The cloud-config snippet (the PVE user-data channel). Hash-named so a config
# change replaces the file and — via replace_triggered_by — the VM.
resource "proxmox_virtual_environment_file" "user_data" {
  for_each = var.instances

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.node_name

  source_raw {
    data      = each.value.user_data
    file_name = "${var.snippet_name_prefix}${each.key}-${substr(md5(each.value.user_data), 0, 8)}.cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.instances

  name      = each.key
  node_name = var.node_name

  description = each.value.description

  clone {
    vm_id = local.template_vm_id
  }

  cpu {
    cores = var.num_cpus
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory
  }

  # Resizes the template's disk on clone — never below it (PVE can't shrink).
  disk {
    datastore_id = var.datastore_id
    interface    = var.disk_interface
    size         = var.disk_size
  }

  network_device {
    bridge = var.bridge
  }

  initialization {
    datastore_id      = var.datastore_id
    interface         = "ide2"
    user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  # The parent dials this VM's guest IP — reported by the QEMU guest agent,
  # which the template must ship.
  agent {
    enabled = true
  }

  stop_on_destroy = true

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_file.user_data[each.key]]
  }
}

locals {
  # First IPv4 on a real NIC (eth*/en*) — the agent also reports lo and, once
  # preview mode installs docker, docker0/veth*, which must not win.
  private_ips = {
    for key, vm in proxmox_virtual_environment_vm.this : key => [
      for idx, name in vm.network_interface_names :
      vm.ipv4_addresses[idx][0]
      if can(regex("^(eth|en)", name)) && length(vm.ipv4_addresses[idx]) > 0
    ][0]
  }
}
