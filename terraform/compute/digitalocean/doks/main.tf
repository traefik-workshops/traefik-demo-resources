resource "digitalocean_kubernetes_cluster" "traefik_demo" {
  name    = var.cluster_name
  region  = var.cluster_location
  version = var.doks_version

  node_pool {
    name       = length(var.worker_nodes) > 0 ? "${var.cluster_name}-${var.worker_nodes[0].label}" : "default"
    size       = var.cluster_node_type
    node_count = length(var.worker_nodes) > 0 ? var.worker_nodes[0].count : var.cluster_node_count
    auto_scale = length(var.worker_nodes) > 0 ? false : var.enable_autoscaling
    min_nodes  = length(var.worker_nodes) > 0 ? null : var.min_nodes
    max_nodes  = length(var.worker_nodes) > 0 ? null : var.max_nodes

    labels = length(var.worker_nodes) > 0 ? {
      node = var.worker_nodes[0].label
    } : {}

    dynamic "taint" {
      for_each = length(var.worker_nodes) > 0 && try(length(var.worker_nodes[0].taint), 0) > 0 ? [var.worker_nodes[0]] : []
      content {
        key    = "node"
        value  = taint.value.taint
        effect = "NoSchedule"
      }
    }
  }
}

resource "digitalocean_kubernetes_node_pool" "worker" {
  for_each   = length(var.worker_nodes) > 1 ? { for wn in slice(var.worker_nodes, 1, length(var.worker_nodes)) : wn.label => wn } : {}
  cluster_id = digitalocean_kubernetes_cluster.traefik_demo.id
  name       = "${var.cluster_name}-${each.key}"
  size       = var.cluster_node_type
  node_count = each.value.count

  labels = {
    node = each.value.label
  }

  dynamic "taint" {
    for_each = try(length(each.value.taint), 0) > 0 ? [each.value.taint] : []
    content {
      key    = "node"
      value  = taint.value
      effect = "NoSchedule"
    }
  }
}

resource "null_resource" "wait" {
  depends_on = [digitalocean_kubernetes_cluster.traefik_demo, digitalocean_kubernetes_node_pool.worker]

  provisioner "local-exec" {
    command = <<EOF
    sleep 30
    EOF
  }
}

resource "null_resource" "doks_cluster" {
  provisioner "local-exec" {
    command = <<EOT
      set -eu

      src=$(mktemp)
      echo '${digitalocean_kubernetes_cluster.traefik_demo.kube_config[0].raw_config}' > "$src"

      mkdir -p "$HOME/.kube"
      # Serialize every read-modify-write of ~/.kube/config: two concurrent
      # standups interleaving flatten+mv would erase each other's context.
      # mkdir is the portable atomic primitive (macOS ships no flock(1)).
      until mkdir ~/.kube/.merge.lock 2>/dev/null; do sleep 1; done
      trap 'rmdir ~/.kube/.merge.lock' EXIT

      # ORDER IS LOAD-BEARING: `kubectl config view --flatten` resolves duplicate names
      # FIRST-WINS, and DigitalOcean names every cluster/user/context it hands out
      # deterministically (do-<region>-<cluster_name>). With the ambient file first,
      # entries left behind by an EARLIER build of a same-named cluster outrank the ones
      # just created: the rename below points the demo context at the right name, but
      # that name still resolves to the previous cluster's dead endpoint and revoked
      # credentials. The first run on a clean machine always works, which is what keeps
      # this hidden (see alibaba/ack for the original postmortem).
      #
      # Listing the new config first makes the cluster we just built win its own name.
      # Only same-named entries are affected, which are precisely the stale DOKS ones.
      merged=$(mktemp)
      KUBECONFIG="$src:$HOME/.kube/config" kubectl config view --flatten > "$merged"
      mv "$merged" "$HOME/.kube/config"
      chmod 600 "$HOME/.kube/config"

      # Explicit KUBECONFIG for the write-back half: an inherited $KUBECONFIG would
      # otherwise send these renames to a different file than the one just written.
      export KUBECONFIG="$HOME/.kube/config"
      kubectl config delete-context "doks-${var.cluster_name}" 2>/dev/null || true
      kubectl config rename-context "do-${var.cluster_location}-${var.cluster_name}" "doks-${var.cluster_name}"
      kubectl config use-context "doks-${var.cluster_name}"

      rm -f "$src"
    EOT
  }

  triggers = {
    always_run = timestamp()
  }

  count      = var.update_kubeconfig ? 1 : 0
  depends_on = [null_resource.wait]
}
