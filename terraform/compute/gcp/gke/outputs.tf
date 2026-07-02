output "host" {
  description = "GKE cluster host (endpoint)"
  value       = google_container_cluster.traefik_demo.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = base64decode(google_container_cluster.traefik_demo.master_auth[0].cluster_ca_certificate)
}

output "token" {
  description = "GKE cluster auth token"
  value       = data.google_client_config.traefik_demo.access_token
  sensitive   = true
}

output "network" {
  description = "VPC network the cluster nodes sit on (the project's default network — the module doesn't create one). Join GCE/Traefik VMs to it so the cluster reaches them privately."
  value       = google_container_cluster.traefik_demo.network
}

output "subnetwork" {
  description = "Subnetwork the cluster nodes sit on"
  value       = google_container_cluster.traefik_demo.subnetwork
}
