data "google_client_config" "traefik_demo" {}

resource "google_container_cluster" "traefik_demo" {
  name                = var.cluster_name
  min_master_version  = var.gke_version
  location            = var.cluster_location
  deletion_protection = false

  # When worker_nodes is set, the first entry configures the default pool.
  # Otherwise, create a plain default pool with cluster_node_count.
  initial_node_count = length(var.worker_nodes) > 0 ? var.worker_nodes[0].count : var.cluster_node_count

  node_config {
    machine_type = var.cluster_node_type
    disk_type    = "pd-standard"

    labels = length(var.worker_nodes) > 0 ? {
      node = var.worker_nodes[0].label
    } : {}

    dynamic "taint" {
      for_each = length(var.worker_nodes) > 0 && try(length(var.worker_nodes[0].taint), 0) > 0 ? [var.worker_nodes[0]] : []
      content {
        key    = "node"
        value  = taint.value.taint
        effect = "NO_SCHEDULE"
      }
    }

    dynamic "workload_metadata_config" {
      for_each = var.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }
  }

  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${data.google_client_config.traefik_demo.project}.svc.id.goog"
    }
  }

  monitoring_config {
    managed_prometheus {
      enabled = false
    }
  }
}

resource "google_container_node_pool" "worker" {
  for_each   = length(var.worker_nodes) > 1 ? { for wn in slice(var.worker_nodes, 1, length(var.worker_nodes)) : wn.label => wn } : {}
  name       = "${google_container_cluster.traefik_demo.name}-${each.key}"
  location   = var.cluster_location
  cluster    = google_container_cluster.traefik_demo.name
  node_count = each.value.count

  node_config {
    machine_type = var.cluster_node_type
    disk_type    = "pd-standard"

    labels = {
      node = each.value.label
    }

    dynamic "taint" {
      for_each = try(length(each.value.taint), 0) > 0 ? [each.value.taint] : []
      content {
        key    = "node"
        value  = taint.value
        effect = "NO_SCHEDULE"
      }
    }

    dynamic "workload_metadata_config" {
      for_each = var.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }
  }
}

resource "google_container_node_pool" "traefik_demo_gpu" {
  name       = "${google_container_cluster.traefik_demo.name}-gpu"
  location   = var.cluster_location
  cluster    = google_container_cluster.traefik_demo.name
  node_count = var.gpu_node_count

  node_config {
    machine_type = var.gpu_node_type
    disk_type    = "pd-standard"

    guest_accelerator {
      type  = var.gpu_type
      count = var.gpu_count
    }

    dynamic "workload_metadata_config" {
      for_each = var.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }
  }

  count = var.enable_gpu ? 1 : 0
}

# The kubeconfig user `get-credentials` writes. `rename-context` renames the CONTEXT
# only, so the user keeps this generated name and stays the handle for set-credentials.
locals {
  kubeconfig_user = "gke_${data.google_client_config.traefik_demo.project}_${var.cluster_location}_${var.cluster_name}"

  # One --exec-env flag per entry. Empty map -> empty string -> the set-credentials
  # line below is omitted entirely, leaving `get-credentials`' output untouched.
  kubeconfig_exec_env_flags = join(" ", [
    for k, v in var.kubeconfig_exec_env : "--exec-env='${k}=${v}'"
  ])
}

resource "null_resource" "gke_cluster" {
  provisioner "local-exec" {
    command = <<EOT
      gcloud container clusters get-credentials ${var.cluster_name} \
        --zone ${var.cluster_location} \
        --project ${data.google_client_config.traefik_demo.project}

      kubectl config delete-context "gke-${var.cluster_name}" 2>/dev/null || true
      kubectl config rename-context "gke_${data.google_client_config.traefik_demo.project}_${var.cluster_location}_${var.cluster_name}" "gke-${var.cluster_name}"
      kubectl config use-context "gke-${var.cluster_name}"
      ${length(var.kubeconfig_exec_env) > 0 ? "kubectl config set-credentials \"${local.kubeconfig_user}\" ${local.kubeconfig_exec_env_flags}" : ""}
    EOT
  }

  triggers = {
    always_run = timestamp()
  }

  count      = var.update_kubeconfig ? 1 : 0
  depends_on = [google_container_cluster.traefik_demo, google_container_node_pool.worker, google_container_node_pool.traefik_demo_gpu]
}
