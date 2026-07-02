resource "kubectl_manifest" "unified_traffic_testrun" {
  yaml_body = yamlencode({
    apiVersion = "k6.io/v1alpha1"
    kind       = "TestRun"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { app = "traefik-hub-load-test" }
    }
    spec = {
      parallelism = var.parallelism
      separate    = false
      quiet       = "false"
      arguments   = "--tag testid=${var.name}"
      script = {
        configMap = {
          name = var.name
          file = "load.js"
        }
      }
    }
  })

  depends_on = [kubectl_manifest.unified_traffic_configmap]
}
