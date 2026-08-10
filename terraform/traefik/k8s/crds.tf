
resource "null_resource" "traefik_crds" {
  count = var.skip_crds ? 0 : 1

  triggers = {
    chart_version = "1.18.0"
    gateway_api   = tostring(!var.skip_gateway_api_crds)
    hub           = tostring(var.enable_api_gateway || var.enable_api_management)
  }

  provisioner "local-exec" {
    # Target a specific cluster when given a kubeconfig (e.g. a cluster created
    # in this same run, so there's no current context yet) and/or an explicit
    # context (several clusters sharing one config). Empty on both = ambient
    # kubeconfig / machine-global current-context — which a parallel standup or
    # an operator switching contexts mid-apply can repoint, so cloud demos
    # should pin kubeconfig_context.
    # `helm repo add` is left unpinned on purpose: it only touches the local
    # repo cache, never a cluster.
    environment = var.kubeconfig != "" ? { KUBECONFIG = var.kubeconfig } : {}
    command     = <<-EOT
      set -euo pipefail
      kctx="${var.kubeconfig_context != "" ? "--context ${var.kubeconfig_context}" : ""}"
      hctx="${var.kubeconfig_context != "" ? "--kube-context ${var.kubeconfig_context}" : ""}"
      helm repo add traefik https://traefik.github.io/charts --force-update
      helm template $hctx traefik-crds traefik/traefik-crds \
        --version 1.18.0 \
        --set gatewayAPI=${var.skip_gateway_api_crds ? "false" : "true"} \
        --set knative=false \
        --set hub=${var.enable_api_gateway || var.enable_api_management ? "true" : "false"} | kubectl $kctx apply --server-side --force-conflicts -f -
    EOT
  }
}
