# Single-node k3s server on a Hyper-V VM — the on-prem "managed k8s" stand-in,
# mirroring compute/proxmox/k3s and compute/vsphere/k3s. Composes the shared
# compute/hyperv/vm primitive (differencing VHDX + NoCloud seed ISO, built
# host-side over WinRM) and installs k3s at first boot (bundled Traefik
# disabled — the traefik/k8s module deploys Hub; k3s's servicelb/klipper stays
# ON, so LoadBalancer Services get the node IP).
#
# STATIC ADDRESSING, unlike the proxmox sibling: Hyper-V has no plan-readable
# guest-IP channel, so the node address is an INPUT (var.ip_address) delivered
# via the NoCloud network-config — which is also what makes `host`/`node_ip`
# known at plan time.
#
# There is no API to fetch k3s's admin kubeconfig (client certs are generated
# on the node at install), so this module SSHes in and reads
# /etc/rancher/k3s/k3s.yaml via an external data source — see kubeconfig.tf
# for the honest prerequisites (on a NAT-internal lab subnet that SSH usually
# rides the operator's WireGuard tunnel).

locals {
  node_ip = split("/", var.ip_address)[0]

  k3s_exec = join(" ", concat(
    ["server", "--disable", "traefik", "--write-kubeconfig-mode", "644"],
    var.tls_san != "" ? ["--tls-san", var.tls_san] : [],
    var.k3s_extra_args,
  ))

  # No qemu-guest-agent here (that is a Proxmox concern): the golden parent
  # bakes linux-cloud-tools (the Hyper-V KVP daemon) instead — baked, because a
  # post-boot install needs a udevadm trigger before the daemon binds.
  user_data = join("\n", ["#cloud-config", yamlencode(merge(
    {
      package_update = true
      runcmd = [
        "curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${var.k3s_channel} sh -s - ${local.k3s_exec}",
      ]
    },
    var.ssh_public_key != "" ? { ssh_authorized_keys = [var.ssh_public_key] } : {},
  ))])

  # NoCloud network-config v2. eth0 is the hv_netvsc synthetic NIC's name on
  # Ubuntu cloud images (predictable naming does not rename netvsc devices).
  network_config = yamlencode({
    version = 2
    ethernets = {
      eth0 = merge(
        {
          addresses = [var.ip_address]
          routes    = [{ to = "default", via = var.gateway }]
        },
        length(var.dns_servers) > 0 ? { nameservers = { addresses = var.dns_servers } } : {},
      )
    }
  })
}

module "vm" {
  source = "../vm"

  host_winrm       = var.host_winrm
  switch_name      = var.switch_name
  parent_vhdx_path = var.parent_vhdx_path
  workdir          = var.workdir
  num_cpus         = var.num_cpus
  memory           = var.memory

  instances = {
    (var.vm_name) = {
      user_data      = local.user_data
      network_config = local.network_config
      ip_address     = local.node_ip
    }
  }
}
