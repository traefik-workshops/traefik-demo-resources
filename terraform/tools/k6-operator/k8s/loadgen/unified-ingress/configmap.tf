resource "kubectl_manifest" "unified_traffic_configmap" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    data = {
      "load.js" = templatefile("${path.module}/scenarios/load.js", {
        domain           = var.domain
        keycloak_url     = var.keycloak_url
        client_id        = var.keycloak_client_id
        client_secret    = var.keycloak_client_secret
        users_json       = local.users_json_escaped
        ai_enabled       = var.ai_enabled ? "true" : "false"
        openai_models    = local.openai_models_json
        anthropic_models = local.anthropic_models_json
        ai_rpm           = var.ai_rpm
        ai_max_tokens    = var.ai_max_tokens
        vus              = var.vus
        duration         = var.duration
      })
    }
  })
}
