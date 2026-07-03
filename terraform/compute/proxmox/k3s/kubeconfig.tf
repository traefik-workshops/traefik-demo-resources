# Kubeconfig retrieval — the honest part.
#
# k3s mints its admin client certs on the node at install time; there is no
# API to fetch them (unlike a managed-k8s control plane). So this module SSHes
# to the VM as var.ssh_user with var.ssh_private_key and cats
# /etc/rancher/k3s/k3s.yaml (world-readable via --write-kubeconfig-mode 644 —
# no sudo needed), rewriting 127.0.0.1 to the VM's guest IP. The script
# retries until k3s has written the file (first boot takes a minute or two),
# so a single apply comes up green.
#
# Prerequisite: the template's default user (var.ssh_user) must accept
# var.ssh_private_key — either bake the public key into the template or pass
# var.ssh_public_key so cloud-init authorizes it at first boot.
data "external" "kubeconfig" {
  program = ["bash", "${path.module}/scripts/kubeconfig.sh"]

  query = {
    host        = local.node_ip
    user        = var.ssh_user
    private_key = var.ssh_private_key
    timeout     = tostring(var.kubeconfig_timeout)
  }
}

locals {
  kubeconfig = base64decode(data.external.kubeconfig.result.kubeconfig_b64)
  kubeparsed = yamldecode(local.kubeconfig)
}
