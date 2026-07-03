# IKS authenticates with an IAM OAuth token (OKE-style, not AKS/ACK client
# certs). host/ca/token come straight off the cluster-config data source; the
# kubeconfig is synthesized from the same trio so callers that want a file
# don't have to.
locals {
  kubeconfig = yamlencode({
    apiVersion        = "v1"
    kind              = "Config"
    "current-context" = var.cluster_name
    clusters = [{
      name = var.cluster_name
      cluster = {
        server                       = data.ibm_container_cluster_config.traefik_demo.host
        "certificate-authority-data" = data.ibm_container_cluster_config.traefik_demo.ca_certificate
      }
    }]
    contexts = [{
      name = var.cluster_name
      context = {
        cluster = var.cluster_name
        user    = var.cluster_name
      }
    }]
    users = [{
      name = var.cluster_name
      user = {
        token = data.ibm_container_cluster_config.traefik_demo.token
      }
    }]
  })
}

output "host" {
  sensitive   = true
  description = "IKS cluster host (public API server endpoint)"
  value       = data.ibm_container_cluster_config.traefik_demo.host
}

output "cluster_ca_certificate" {
  sensitive   = true
  description = "IKS cluster CA certificate (PEM)"
  value       = base64decode(data.ibm_container_cluster_config.traefik_demo.ca_certificate)
}

output "token" {
  sensitive   = true
  description = "IKS cluster auth token (IAM OAuth token — short-lived, refreshed on every terraform read)"
  value       = data.ibm_container_cluster_config.traefik_demo.token
}

output "kubeconfig" {
  sensitive   = true
  description = "IKS cluster kubeconfig (synthesized from host/CA/token)"
  value       = local.kubeconfig
}

output "cluster_id" {
  sensitive   = true
  description = "IKS cluster ID"
  value       = ibm_container_vpc_cluster.traefik_demo.id
}

output "crn" {
  description = "IKS cluster CRN — what an IAM trusted profile's compute-resource claim rule (cr_type \"IKS_SA\") scopes on to trust in-cluster workloads"
  value       = ibm_container_vpc_cluster.traefik_demo.crn
}

output "vpc_id" {
  description = "ID of the VPC the cluster landed in — VM spokes (apps/whoami/ibm-vpc, traefik/ibm-vpc) join it"
  value       = local.vpc_id
}
