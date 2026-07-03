# whoami on Proxmox VE guests — the on-prem sibling of apps/whoami/vsphere /
# apps/whoami/ec2 / apps/whoami/gce, targeting the open-source
# github.com/NX211/traefik-proxmox-provider Traefik PLUGIN (see
# traefik/proxmox-vm), not a first-party hub provider.
#
# THE LABEL FORMAT IS LINES, NOT JSON: the plugin reads each guest's
# Notes/description field LINE BY LINE — one `traefik.key=value` per line
# (`traefik.enable=true` is mandatory; the parser lowercases keys). Each app's
# `traefik_labels` map is rendered as that line format into the guest
# description. NOT the vsphere sibling's JSON blob, NOT EC2/Azure dotted tags.
#
# ONE SERVICE PER GUEST — no server merging (verified against the plugin
# source, v0.8.1): each labeled service gets EXACTLY ONE server (the guest's
# IP), and a same-named service on another guest OVERWRITES it (last write
# wins). Identical labels on N replicas do NOT merge into one N-server service
# like the vsphere/EC2 providers — give every guest UNIQUE service names and
# compose the spread upstream (e.g. a weighted file-provider service on the
# gateway; see demos/proxmox-unified-ingress).
#
# Two guest types per app (`type`):
#   "vm" (default) — a QEMU clone of a cloud-init-enabled Ubuntu cloud-image
#   template, docker-running the whoami fork via whoami/cloud-init like every
#   sibling.
#   "lxc" — a container from an OS template (Debian). LXC has NO cloud-init
#   user-data path, so whoami is the UPSTREAM BINARY (traefik/whoami release)
#   installed through `pct exec` over SSH to the Proxmox node and run by the
#   container's systemd — see the honest limitations in the README.

module "cloud_init" {
  for_each = local.vm_apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(var.apps[each.value].port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-qemu).
  name = try(var.apps[each.value].name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(var.apps[each.value].environment, {}))
}

locals {
  # Replicate the siblings' instance-key scheme: "<app>-<replica>".
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key            = "${app_name}-${replica_idx + 1}"
        app_name       = app_name
        type           = try(app_config.type, "vm")
        port           = try(app_config.port, 80)
        name           = try(app_config.name, "")
        environment    = merge(var.environment, try(app_config.environment, {}))
        traefik_labels = try(app_config.traefik_labels, {})
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }
  vm_instances  = { for k, inst in local.instances_map : k => inst if inst.type == "vm" }
  lxc_instances = { for k, inst in local.instances_map : k => inst if inst.type == "lxc" }

  vm_apps = toset([for k, inst in local.vm_instances : inst.app_name])

  # The NX211 plugin's line format: one `key=value` per line in the description.
  descriptions = {
    for k, inst in local.instances_map :
    k => join("\n", [for lk, lv in inst.traefik_labels : "${lk}=${lv}"])
  }
}

# Resolve template_name -> VMID when the QEMU template is given by name.
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

# --- QEMU VMs (type = "vm") ---------------------------------------------------

# One cloud-config snippet per VM instance (replicas render identically, but
# per-instance files keep the replace_triggered_by below on each.key — the
# only index terraform allows there). Hash-named so a content change replaces
# the file — and, with it, the VM (cloud-init runs on first boot only).
resource "proxmox_virtual_environment_file" "user_data" {
  for_each = local.vm_instances

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.node_name

  source_raw {
    data      = module.cloud_init[each.value.app_name].rendered
    file_name = "whoami-${each.key}-${substr(md5(module.cloud_init[each.value.app_name].rendered), 0, 8)}.cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "whoami" {
  for_each = local.vm_instances

  name      = each.key
  node_name = var.node_name

  # The plugin's workload config: traefik.* labels, one per line, in the Notes.
  description = length(each.value.traefik_labels) > 0 ? local.descriptions[each.key] : null

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

  # The `instances` output reads the QEMU-agent-reported IP — also what gates
  # the plugin's discovery (it queries the agent for VM addresses): no agent,
  # no server URL. The template must ship qemu-guest-agent.
  agent {
    enabled = true
  }

  stop_on_destroy = true

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_file.user_data[each.key]]
  }
}

# --- LXC containers (type = "lxc") ----------------------------------------------

resource "proxmox_virtual_environment_container" "whoami" {
  for_each = local.lxc_instances

  node_name = var.node_name

  # Same line-format labels — the plugin reads container Notes identically
  # (container IPs come from the PVE lxc interfaces endpoint, no agent).
  description = length(each.value.traefik_labels) > 0 ? local.descriptions[each.key] : null

  unprivileged = true

  operating_system {
    template_file_id = var.lxc_template_file_id
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
    size         = var.lxc_disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  # systemd inside an unprivileged container wants nesting (the PVE default
  # for new CTs; setting features may need elevated token privileges).
  features {
    nesting = true
  }

  started = true

  lifecycle {
    precondition {
      condition     = var.lxc_template_file_id != ""
      error_message = "lxc_template_file_id is required for apps with type = \"lxc\"."
    }
  }
}

locals {
  # Systemd unit run by the container's init. Delivered base64-encoded through
  # the setup script (no nested-heredoc quoting). systemd strips leading
  # whitespace, so heredoc indentation is harmless.
  lxc_units = { for k, inst in local.lxc_instances : k => <<-EOT
    [Unit]
    Description=whoami (upstream binary)
    After=network-online.target
    Wants=network-online.target

    [Service]
    ${join("\n", [for ek, ev in inst.environment : "Environment=\"${ek}=${ev}\""])}
    ExecStart=/usr/local/bin/whoami --port ${inst.port}${inst.name != "" ? " --name ${inst.name}" : ""} --verbose
    Restart=always

    [Install]
    WantedBy=multi-user.target
  EOT
  }

  # Runs INSIDE the container (pushed + executed via pct from the PVE node).
  lxc_setup = { for k, inst in local.lxc_instances : k => <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    # Wait for DHCP + DNS inside the container before touching the network.
    for i in $(seq 1 60); do getent hosts deb.debian.org >/dev/null 2>&1 && break; sleep 2; done
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl ca-certificates
    curl -fsSL --retry 5 "https://github.com/traefik/whoami/releases/download/${var.lxc_whoami_version}/whoami_${var.lxc_whoami_version}_linux_amd64.tar.gz" -o /tmp/whoami.tar.gz
    tar -xzf /tmp/whoami.tar.gz -C /usr/local/bin whoami
    chmod +x /usr/local/bin/whoami
    echo "${base64encode(local.lxc_units[k])}" | base64 -d >/etc/systemd/system/whoami.service
    systemctl daemon-reload
    systemctl enable --now whoami
    echo "whoami LXC provisioning complete"
  EOT
  }
}

# Install whoami inside the container. Pure terraform can't run arbitrary
# provisioning inside an LXC guest (no cloud-init user-data path), so this
# SSHes to the PROXMOX NODE and `pct push` + `pct exec`s the setup script —
# the same node access the provider's snippet upload already needs.
resource "terraform_data" "lxc_whoami" {
  for_each = local.lxc_instances

  # Re-provision when the container is recreated or the script changes.
  triggers_replace = [
    proxmox_virtual_environment_container.whoami[each.key].id,
    sha1(local.lxc_setup[each.key]),
  ]

  connection {
    type        = "ssh"
    host        = var.node_ssh.host
    user        = var.node_ssh.user
    private_key = var.node_ssh.private_key
  }

  provisioner "file" {
    content     = local.lxc_setup[each.key]
    destination = "/tmp/whoami-${each.key}-setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "pct push ${proxmox_virtual_environment_container.whoami[each.key].id} /tmp/whoami-${each.key}-setup.sh /tmp/whoami-setup.sh",
      "pct exec ${proxmox_virtual_environment_container.whoami[each.key].id} -- bash /tmp/whoami-setup.sh",
      "rm -f /tmp/whoami-${each.key}-setup.sh",
    ]
  }

  lifecycle {
    precondition {
      condition     = var.node_ssh != null
      error_message = "node_ssh (SSH access to the Proxmox node) is required for apps with type = \"lxc\" — whoami is installed via pct exec."
    }
  }
}
