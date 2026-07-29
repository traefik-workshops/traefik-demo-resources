# Single-node k3s server on a Proxmox VE VM — the on-prem "managed k8s"
# stand-in, mirroring compute/vsphere/k3s. Clones a cloud-init-enabled Ubuntu
# cloud-image template and installs k3s at first boot (bundled Traefik
# disabled — the traefik/k8s module deploys Hub; k3s's servicelb/klipper stays
# ON, so LoadBalancer Services get the node IP).
#
# Proxmox delivers cloud-init as a SNIPPET file on a datastore, not an inline
# blob (vSphere's guestinfo): the cloud-config is uploaded with
# proxmox_virtual_environment_file (content_type=snippets — the bpg provider
# pushes snippets over SSH, so its `ssh {}` block must be configured and the
# datastore must allow Snippets content) and referenced from the VM's
# initialization block via user_data_file_id.
#
# There is no API to fetch k3s's admin kubeconfig (client certs are generated
# on the node at install), so this module SSHes in and reads
# /etc/rancher/k3s/k3s.yaml via an external data source — see kubeconfig.tf
# for the honest prerequisites.

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

  k3s_exec = join(" ", concat(
    ["server", "--disable", "traefik", "--write-kubeconfig-mode", "644"],
    var.tls_san != "" ? ["--tls-san", var.tls_san] : [],
    var.k3s_extra_args,
  ))

  # qemu-guest-agent belt-and-braces: the IP outputs and the agent{} wait below
  # need it. An agent-baked template makes this a no-op; on a plain Ubuntu
  # cloud image cloud-init installs it while terraform is still waiting on the
  # agent, so the wait resolves either way.
  user_data = join("\n", ["#cloud-config", yamlencode(merge(
    {
      package_update = true
      packages       = ["qemu-guest-agent"]
      runcmd = [
        "systemctl enable --now qemu-guest-agent",
        "curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${var.k3s_channel} sh -s - ${local.k3s_exec}",
      ]
    },
    var.ssh_public_key != "" ? { ssh_authorized_keys = [var.ssh_public_key] } : {},
  ))])
}

# The cloud-config snippet. The name carries a content hash so a user-data
# change replaces the file (new ID) and — via replace_triggered_by — the VM,
# because cloud-init only runs on first boot.
resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.node_name

  source_raw {
    data      = local.user_data
    file_name = "${var.vm_name}-${substr(md5(local.user_data), 0, 8)}.cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "k3s" {
  name      = var.vm_name
  node_name = var.node_name

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

  # Resizes the template's disk in place on clone — never below it (PVE
  # refuses to shrink); interface must name the disk the template actually has.
  disk {
    datastore_id = var.datastore_id
    interface    = var.disk_interface
    size         = var.disk_size
  }

  network_device {
    bridge = var.bridge
  }

  # DHCP via cloud-init; hostname/instance-id ride the PVE-generated meta-data
  # (derived from the VM name).
  initialization {
    datastore_id      = var.datastore_id
    interface         = "ide2"
    user_data_file_id = proxmox_virtual_environment_file.user_data.id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  # The kubeconfig fetch (kubeconfig.tf) and the IP outputs read the guest IP
  # from the QEMU guest agent — no agent, no address, and the apply hangs here.
  agent {
    enabled = true
  }

  # Hard-stop on destroy: a graceful ACPI shutdown can hang teardown when the
  # guest is wedged mid-install.
  stop_on_destroy = true

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_file.user_data]
  }
}

locals {
  # First IPv4 on a real NIC (eth*/en*) — the agent also reports lo (and, on
  # docker-running guests, docker0/veth*), which must not win.
  node_ip = [
    for idx, name in proxmox_virtual_environment_vm.k3s.network_interface_names :
    proxmox_virtual_environment_vm.k3s.ipv4_addresses[idx][0]
    if can(regex("^(eth|en)", name)) && length(proxmox_virtual_environment_vm.k3s.ipv4_addresses[idx]) > 0
  ][0]
}
