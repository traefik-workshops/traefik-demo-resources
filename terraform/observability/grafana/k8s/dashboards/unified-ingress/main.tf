resource "kubernetes_config_map_v1" "grafana_unified_ingress_dashboard" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  data = {
    "dashboard.json" = file("${path.module}/dashboard.json")
  }
}
