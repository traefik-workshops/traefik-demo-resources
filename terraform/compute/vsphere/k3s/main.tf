# Single-node k3s server on a vSphere VM — the on-prem "managed k8s" stand-in.
# Clones a cloud-init-enabled Ubuntu cloud-image template and installs k3s at
# first boot (bundled Traefik disabled — the traefik/k8s module deploys Hub;
# k3s's servicelb/klipper stays ON, so LoadBalancer Services get the node IP).
#
# There is no API to fetch k3s's admin kubeconfig (client certs are generated
# on the node at install), so this module SSHes in and reads
# /etc/rancher/k3s/k3s.yaml via an external data source — see kubeconfig.tf
# for the honest prerequisites.

data "vsphere_datacenter" "this" {
  name = var.datacenter
}

data "vsphere_datastore" "this" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.this.id
}

# Placement: a compute cluster (its root resource pool) or an explicit
# resource pool — exactly one of var.cluster / var.resource_pool.
data "vsphere_compute_cluster" "this" {
  count         = var.resource_pool == "" ? 1 : 0
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_resource_pool" "this" {
  count         = var.resource_pool != "" ? 1 : 0
  name          = var.resource_pool
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_network" "this" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template
  datacenter_id = data.vsphere_datacenter.this.id
}

locals {
  resource_pool_id = var.resource_pool != "" ? data.vsphere_resource_pool.this[0].id : data.vsphere_compute_cluster.this[0].resource_pool_id

  k3s_exec = join(" ", concat(
    ["server", "--disable", "traefik", "--write-kubeconfig-mode", "644"],
    var.tls_san != "" ? ["--tls-san", var.tls_san] : [],
    var.k3s_extra_args,
  ))

  # Delivered over the guestinfo cloud-init channel (extra_config below) — the
  # standard datasource on cloud-image templates cloned outside a cloud.
  user_data = join("\n", ["#cloud-config", yamlencode(merge(
    {
      package_update = true
      runcmd = [
        "curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${var.k3s_channel} sh -s - ${local.k3s_exec}",
      ]
    },
    var.ssh_public_key != "" ? { ssh_authorized_keys = [var.ssh_public_key] } : {},
  ))])

  metadata = jsonencode(merge(
    {
      "instance-id"    = var.vm_name
      "local-hostname" = var.vm_name
    },
    # DHCP by default — cloud-init's fallback network config. A static address is wired
    # through the guestinfo datasource's network-config v2 when the network has no DHCP
    # (or when this node's address must be known before it boots).
    var.static_ip == "" ? {} : {
      network = {
        version = 2
        ethernets = {
          ens192 = {
            addresses   = [var.static_ip]
            nameservers = { addresses = var.static_nameservers }
            routes      = var.static_gateway == "" ? [] : [{ to = "default", via = var.static_gateway }]
          }
        }
      }
    },
  ))
}

resource "vsphere_virtual_machine" "k3s" {
  name             = var.vm_name
  resource_pool_id = local.resource_pool_id
  datastore_id     = data.vsphere_datastore.this.id
  folder           = var.folder != "" ? var.folder : null

  num_cpus = var.num_cpus
  memory   = var.memory

  # Inherit the template's hardware identity so the clone boots unchanged.
  guest_id  = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type
  firmware  = data.vsphere_virtual_machine.template.firmware

  network_interface {
    network_id   = data.vsphere_network.this.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label = "disk0"
    # Never below the template's disk — vSphere refuses to shrink on clone.
    size             = max(data.vsphere_virtual_machine.template.disks[0].size, var.disk_size)
    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks[0].eagerly_scrub
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  # See compute/vsphere/vm: a stock cloud-image OVA declares vApp properties with the
  # `iso` OVF transport, and vSphere then requires a CLIENT cdrom on the CLONE (not just
  # on the template). Nothing is mounted; cloud-init rides the guestinfo keys below.
  cdrom {
    client_device = true
  }

  extra_config = {
    "guestinfo.userdata"          = base64encode(local.user_data)
    "guestinfo.userdata.encoding" = "base64"
    "guestinfo.metadata"          = base64encode(local.metadata)
    "guestinfo.metadata.encoding" = "base64"
  }

  # The kubeconfig fetch (kubeconfig.tf) and the module's IP outputs both need
  # a guest IP, reported by open-vm-tools (Ubuntu cloud images ship it).
  wait_for_guest_net_timeout = 10
}
