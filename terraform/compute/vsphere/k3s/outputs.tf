output "host" {
  description = "Kubernetes API endpoint (https://<vm-ip>:6443)"
  value       = "https://${vsphere_virtual_machine.k3s.default_ip_address}:6443"
}

output "node_ip" {
  description = "The VM's guest IP — also where klipper (k3s servicelb) publishes LoadBalancer Services, so point demo DNS / /etc/hosts entries here"
  value       = vsphere_virtual_machine.k3s.default_ip_address
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

output "vm_id" {
  description = "vSphere managed object ID of the k3s VM"
  value       = vsphere_virtual_machine.k3s.id
}

output "vm_name" {
  description = "Name of the k3s VM"
  value       = vsphere_virtual_machine.k3s.name
}
