output "host" {
  description = "Kubernetes API endpoint (https://<static-node-ip>:6443) — known at PLAN time (static addressing)"
  value       = "https://${local.node_ip}:6443"
}

output "node_ip" {
  description = "The VM's static guest IP — also where klipper (k3s servicelb) publishes LoadBalancer Services, so point demo DNS / /etc/hosts entries here. An INPUT echoed back (Hyper-V has no plan-readable discovery), so it is plan-known."
  value       = local.node_ip
}

output "kubeconfig" {
  description = "Admin kubeconfig (server rewritten from 127.0.0.1 to the VM IP)"
  value       = local.kubeconfig
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (PEM)"
  value       = base64decode(local.kubeparsed.clusters[0].cluster["certificate-authority-data"])
}

output "client_certificate" {
  description = "Admin client certificate (PEM) — k3s auth is cert-based, AKS/k3d-style"
  value       = base64decode(local.kubeparsed.users[0].user["client-certificate-data"])
}

output "client_key" {
  description = "Admin client key (PEM)"
  value       = base64decode(local.kubeparsed.users[0].user["client-key-data"])
  sensitive   = true
}

output "vm_name" {
  description = "Name of the k3s VM (no numeric VMID on Hyper-V — the name IS the identity)"
  value       = var.vm_name
}
