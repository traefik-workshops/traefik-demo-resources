output "repo_url" {
  description = "The clone/push URL for the config repo — https://git.<domain>/config.git. Spokes pull from it; terraform pushes to it."
  value       = "https://${var.ingress_host}/config.git"
}

output "service_name" {
  description = "In-cluster Service name (for anything that reaches the repo without going through ingress)."
  value       = kubernetes_service_v1.git.metadata[0].name
}
