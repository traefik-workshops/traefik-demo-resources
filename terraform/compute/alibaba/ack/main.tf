# Managed ACK cluster — the Alibaba sibling of compute/azure/aks and
# compute/oracle/oke. Joins the provided vswitches (e.g. compute/alibaba/vpc's
# vswitch_ids) instead of creating its own network; nodes live in separate
# node-pool resources (a default pool, or per-role pools when worker_nodes is
# set), matching the AKS/OKE surface.

resource "alicloud_cs_managed_kubernetes" "traefik_demo" {
  name         = var.cluster_name
  cluster_spec = var.cluster_spec
  version      = var.ack_version != "" ? var.ack_version : null

  vswitch_ids       = var.vswitch_ids
  security_group_id = var.security_group_id != "" ? var.security_group_id : null

  # SNAT via a module-created NAT gateway — without it, nodes in the provided
  # vswitches have no outbound internet and can't pull images.
  new_nat_gateway = var.enable_nat_gateway

  # Public API server endpoint (the demo laptop dials it directly).
  slb_internet_enabled = true

  pod_cidr     = var.pod_cidr
  service_cidr = var.service_cidr

  deletion_protection = false
}

# When worker_nodes is empty, create a single default pool.
# When worker_nodes is set, create per-role pools instead.
resource "alicloud_cs_kubernetes_node_pool" "traefik_demo" {
  count = length(var.worker_nodes) == 0 ? 1 : 0

  cluster_id     = alicloud_cs_managed_kubernetes.traefik_demo.id
  node_pool_name = "${var.cluster_name}-pool"
  vswitch_ids    = var.vswitch_ids
  instance_types = [var.cluster_node_type]
  desired_size   = var.cluster_node_count

  system_disk_category = var.node_disk_category
  system_disk_size     = var.node_disk_size
}

resource "alicloud_cs_kubernetes_node_pool" "worker" {
  for_each = { for wn in var.worker_nodes : wn.label => wn }

  cluster_id     = alicloud_cs_managed_kubernetes.traefik_demo.id
  node_pool_name = "${var.cluster_name}-${each.key}"
  vswitch_ids    = var.vswitch_ids
  instance_types = [var.cluster_node_type]
  desired_size   = each.value.count

  system_disk_category = var.node_disk_category
  system_disk_size     = var.node_disk_size

  labels {
    key   = "node"
    value = each.value.label
  }

  # Unlike OKE, ACK node pools support native taints — no kubectl post-step.
  dynamic "taints" {
    for_each = try(length(each.value.taint), 0) > 0 ? [each.value.taint] : []
    content {
      key    = "node"
      value  = taints.value
      effect = "NoSchedule"
    }
  }
}

data "alicloud_cs_cluster_credential" "kubeconfig" {
  cluster_id = alicloud_cs_managed_kubernetes.traefik_demo.id

  depends_on = [alicloud_cs_kubernetes_node_pool.traefik_demo, alicloud_cs_kubernetes_node_pool.worker]
}

resource "null_resource" "ack_cluster" {
  provisioner "local-exec" {

    command = <<EOT
      set -eu

      src=$(mktemp)
      echo '${data.alicloud_cs_cluster_credential.kubeconfig.kube_config}' > "$src"
      # Get the current context name from the ACK kubeconfig
      ACK_CONTEXT=$(kubectl --kubeconfig="$src" config current-context)

      mkdir -p "$HOME/.kube"
      # Serialize every read-modify-write of ~/.kube/config: two concurrent
      # standups interleaving flatten+mv would erase each other's context.
      # mkdir is the portable atomic primitive (macOS ships no flock(1)).
      until mkdir ~/.kube/.merge.lock 2>/dev/null; do sleep 1; done
      trap 'rmdir ~/.kube/.merge.lock' EXIT

      # ORDER IS LOAD-BEARING: `kubectl config view --flatten` resolves duplicate names
      # FIRST-WINS, and ACK names every cluster it hands out plain `kubernetes`. With the
      # ambient file first, a `kubernetes` entry left behind by an EARLIER ACK cluster
      # outranks the one just created: the context below gets renamed and points at the
      # right name, but that name still resolves to the previous cluster's dead endpoint.
      #
      # It fails as a connection timeout to an address nothing in this run ever mentions
      # (2026-08-04: the CRD install dialed 8.222.142.86 while the live API server was
      # 8.219.49.205), and it hits any operator who has stood this demo up before -- the
      # first run on a clean machine always works, which is what kept it hidden.
      #
      # Listing the new config first makes the cluster we just built win its own name.
      # Only same-named entries are affected, which are precisely the stale ACK ones.
      merged=$(mktemp)
      KUBECONFIG="$src:$HOME/.kube/config" kubectl config view --flatten > "$merged"
      mv "$merged" "$HOME/.kube/config"
      chmod 600 "$HOME/.kube/config"

      # Explicit KUBECONFIG for the write-back half: an inherited $KUBECONFIG would
      # otherwise send these renames to a different file than the one just written.
      export KUBECONFIG="$HOME/.kube/config"
      kubectl config delete-context "ack-${var.cluster_name}" 2>/dev/null || true
      kubectl config rename-context "$ACK_CONTEXT" "ack-${var.cluster_name}"
      kubectl config use-context "ack-${var.cluster_name}"

      rm -f "$src"
    EOT
  }

  triggers = {
    always_run = timestamp()
  }

  count      = var.update_kubeconfig ? 1 : 0
  depends_on = [alicloud_cs_managed_kubernetes.traefik_demo, alicloud_cs_kubernetes_node_pool.traefik_demo, alicloud_cs_kubernetes_node_pool.worker]
}
