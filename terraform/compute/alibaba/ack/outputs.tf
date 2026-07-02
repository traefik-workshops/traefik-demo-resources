# ACK kubeconfigs authenticate with a client certificate (no token), so the
# credential outputs mirror compute/azure/aks: host + CA + client cert/key,
# parsed out of the kubeconfig the alicloud_cs_cluster_credential data source
# returns (the OKE parse-the-kubeconfig pattern).
locals {
  kubeconfig_raw  = data.alicloud_cs_cluster_credential.kubeconfig.kube_config
  kubeconfig      = yamldecode(local.kubeconfig_raw)
  cluster         = local.kubeconfig.clusters[0].cluster
  cluster_server  = local.cluster.server
  cluster_ca_cert = base64decode(local.cluster["certificate-authority-data"])
  user            = local.kubeconfig.users[0].user
  client_cert     = base64decode(local.user["client-certificate-data"])
  client_key      = base64decode(local.user["client-key-data"])
}

output "host" {
  sensitive   = true
  description = "ACK cluster host (public API server endpoint)"
  value       = local.cluster_server
}

output "cluster_ca_certificate" {
  sensitive   = true
  description = "ACK cluster CA certificate"
  value       = local.cluster_ca_cert
}

output "client_certificate" {
  sensitive   = true
  description = "ACK cluster client certificate (ACK kubeconfigs are cert-based — there is no token)"
  value       = local.client_cert
}

output "client_key" {
  sensitive   = true
  description = "ACK cluster client key"
  value       = local.client_key
}

output "kubeconfig" {
  sensitive   = true
  description = "ACK cluster kubeconfig"
  value       = local.kubeconfig_raw
}

output "cluster_id" {
  sensitive   = true
  description = "ACK cluster ID"
  value       = alicloud_cs_managed_kubernetes.traefik_demo.id
}

output "vpc_id" {
  description = "ID of the VPC the cluster landed in — ECS/ECI spokes (apps/whoami/alibaba-*, traefik/alibaba-*) join it"
  value       = alicloud_cs_managed_kubernetes.traefik_demo.vpc_id
}
