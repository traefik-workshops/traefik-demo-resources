resource "linode_lke_cluster" "traefik_demo" {
  label       = var.cluster_name
  region      = var.cluster_location
  k8s_version = var.lke_version

  control_plane {
    high_availability = var.control_plane_high_availability
  }

  # When worker_nodes is empty, create a single default pool.
  # When worker_nodes is set, create per-role pools instead.
  dynamic "pool" {
    for_each = length(var.worker_nodes) == 0 ? ["default"] : []
    content {
      type   = var.cluster_node_type
      count  = var.cluster_node_count
      labels = var.node_labels
    }
  }

  dynamic "pool" {
    for_each = var.worker_nodes
    content {
      type  = var.cluster_node_type
      count = pool.value.count

      labels = {
        node = pool.value.label
      }

      dynamic "taint" {
        for_each = try(length(pool.value.taint), 0) > 0 ? [pool.value.taint] : []
        content {
          key    = "node"
          value  = taint.value
          effect = "NoSchedule"
        }
      }
    }
  }

  dynamic "pool" {
    for_each = var.enable_gpu ? ["gpu"] : []
    content {
      type   = var.gpu_node_type
      count  = var.gpu_node_count
      labels = var.node_labels
    }
  }
}

resource "null_resource" "wait" {
  depends_on = [linode_lke_cluster.traefik_demo]

  provisioner "local-exec" {
    command = <<EOF
    sleep 30
    EOF
  }
}

resource "null_resource" "lke_cluster" {
  provisioner "local-exec" {

    command = <<EOT
      set -eu

      src=$(mktemp)
      echo '${local.kubeconfig_raw}' > "$src"

      mkdir -p "$HOME/.kube"
      # Serialize every read-modify-write of ~/.kube/config: two concurrent
      # standups interleaving flatten+mv would erase each other's context. Held
      # through the renames below — they rewrite the same file. mkdir is the
      # portable atomic primitive (macOS ships no flock(1)).
      until mkdir ~/.kube/.merge.lock 2>/dev/null; do sleep 1; done
      trap 'rmdir ~/.kube/.merge.lock' EXIT

      # New config first in the flatten: duplicate names resolve FIRST-WINS, so the
      # cluster just built wins any same-named stale entry (see alibaba/ack for the
      # full postmortem; LKE's generated names embed the cluster id so collisions
      # are rare, but the cheap ordering guarantee beats relying on that).
      merged=$(mktemp)
      KUBECONFIG="$src:$HOME/.kube/config" kubectl config view --flatten > "$merged"
      mv "$merged" "$HOME/.kube/config"
      chmod 600 "$HOME/.kube/config"

      # Explicit KUBECONFIG for the write-back half: an inherited $KUBECONFIG would
      # otherwise send these renames to a different file than the one just written.
      export KUBECONFIG="$HOME/.kube/config"
      kubectl config delete-context "${var.cluster_name_prefix}${var.cluster_name}" 2>/dev/null || true
      kubectl config rename-context "lke${linode_lke_cluster.traefik_demo.id}-ctx" "${var.cluster_name_prefix}${var.cluster_name}"
      kubectl config use-context "${var.cluster_name_prefix}${var.cluster_name}"

      rm -f "$src"
    EOT
  }

  triggers = {
    always_run = timestamp()
  }

  count      = var.update_kubeconfig ? 1 : 0
  depends_on = [null_resource.wait]
}
