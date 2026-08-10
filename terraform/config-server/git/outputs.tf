output "repo_url" {
  description = "The clone/push URL for the config repo — https://git.<domain>/config.git. Spokes pull from it; terraform pushes to it."
  value       = "https://${var.ingress_host}/config.git"
}

output "raw_base_url" {
  description = "Base URL the pushed tree is served RAW under — https://git.<domain>/config. A Hub provider's configEndpoint is <this>/<path-in-files> (the URL path's extension picks the decoder: yaml default / json / toml)."
  value       = "https://${var.ingress_host}/config"
}

output "service_name" {
  description = "In-cluster Service name (for anything that reaches the repo without going through ingress)."
  value       = kubernetes_service_v1.git.metadata[0].name
}
