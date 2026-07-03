# Kubeconfig retrieval — the honest part.
#
# k3s mints its admin client certs on the node at install time; there is no
# API to fetch them (unlike a managed-k8s control plane). So this module SSHes
# to the instance as var.ssh_user with var.ssh_private_key and cats
# /etc/rancher/k3s/k3s.yaml (world-readable via --write-kubeconfig-mode 644 —
# no sudo needed), rewriting 127.0.0.1 to the instance's primary IP. The script
# retries until k3s has written the file — the retry loop also absorbs the
# postProvision bootstrap's timing — so a single apply comes up green.
#
# Prerequisite: var.ssh_user must accept var.ssh_private_key — pass
# var.ssh_public_key so the bootstrap authorizes it, or bake the key into the
# virtual image.
data "external" "kubeconfig" {
  program = ["bash", "${path.module}/scripts/kubeconfig.sh"]

  query = {
    # connection_info[0] is Morpheus's primary connection address (the
    # gomorpheus provider surfaced it as primary_ip_address).
    host        = hpe_morpheus_instance.k3s.connection_info[0]
    user        = var.ssh_user
    private_key = var.ssh_private_key
    timeout     = tostring(var.kubeconfig_timeout)
  }
}

locals {
  kubeconfig = base64decode(data.external.kubeconfig.result.kubeconfig_b64)
  kubeparsed = yamldecode(local.kubeconfig)
}
