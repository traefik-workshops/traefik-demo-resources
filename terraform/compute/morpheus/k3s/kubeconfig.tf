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

# Ambient-kubeconfig merge — the on-prem analogue of the cloud modules' CLI
# merges (`aws eks update-kubeconfig` & co). k3s names its context/cluster/user
# all `default`, which would collide across demos, so everything is renamed to
# k3s-<vm_name> before merging. The rendered config is handed to the script via
# environment so client certs never appear in the local-exec command echo.
locals {
  ambient_context = "k3s-${var.vm_name}"
  kubeconfig_ambient = yamlencode({
    apiVersion        = "v1"
    kind              = "Config"
    "current-context" = local.ambient_context
    clusters          = [{ name = local.ambient_context, cluster = local.kubeparsed.clusters[0].cluster }]
    users             = [{ name = local.ambient_context, user = local.kubeparsed.users[0].user }]
    contexts          = [{ name = local.ambient_context, context = { cluster = local.ambient_context, user = local.ambient_context } }]
  })
}

resource "null_resource" "update_kubeconfig" {
  count = var.update_kubeconfig ? 1 : 0

  provisioner "local-exec" {
    environment = { K3S_KUBECONFIG = local.kubeconfig_ambient }
    # New file first in KUBECONFIG so a re-created cluster's fresh certs/IP win
    # over any stale ambient entry of the same name.
    command = <<-EOT
      set -e
      tmp=$(mktemp)
      printf '%s' "$K3S_KUBECONFIG" > "$tmp"
      mkdir -p "$HOME/.kube"
      merged=$(mktemp)
      KUBECONFIG="$tmp:$HOME/.kube/config" kubectl config view --flatten > "$merged"
      mv "$merged" "$HOME/.kube/config"
      chmod 600 "$HOME/.kube/config"
      rm -f "$tmp"
      kubectl config use-context "${local.ambient_context}"
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}
