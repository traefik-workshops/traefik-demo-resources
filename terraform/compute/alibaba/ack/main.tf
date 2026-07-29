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
      echo '${data.alicloud_cs_cluster_credential.kubeconfig.kube_config}' > ack-kubeconfig.yaml
      # Get the current context name from the ACK kubeconfig
      ACK_CONTEXT=$(kubectl --kubeconfig=ack-kubeconfig.yaml config current-context)

      export KUBECONFIG=~/.kube/config:ack-kubeconfig.yaml
      kubectl config view --flatten > merged.yaml
      mv merged.yaml ~/.kube/config

      kubectl config delete-context "ack-${var.cluster_name}" 2>/dev/null || true
      kubectl config rename-context "$ACK_CONTEXT" "ack-${var.cluster_name}"
      kubectl config use-context "ack-${var.cluster_name}"

      rm ack-kubeconfig.yaml
    EOT
  }

  triggers = {
    always_run = timestamp()
  }

  count      = var.update_kubeconfig ? 1 : 0
  depends_on = [alicloud_cs_managed_kubernetes.traefik_demo, alicloud_cs_kubernetes_node_pool.traefik_demo, alicloud_cs_kubernetes_node_pool.worker]
}
