output "id" {
  description = "BMC server ID."
  value       = pnap_server.metal.id
}

output "public_ip" {
  description = "Primary public IP — where the operator (and the demo's terraform) reaches the hypervisor API (Proxmox :8006, ESXi/VCSA :443, Morpheus manager)."
  # public_ip_addresses is a SET — sort() for a deterministic pick of the first.
  value = try(sort(pnap_server.metal.public_ip_addresses)[0], "")
}

output "public_ip_addresses" {
  description = "All public IPs assigned to the server."
  value       = pnap_server.metal.public_ip_addresses
}

output "private_ip_addresses" {
  description = "Private (backend-network) IPs."
  value       = pnap_server.metal.private_ip_addresses
}

output "os" {
  description = "The OS image the server was provisioned with."
  value       = pnap_server.metal.os
}

output "password" {
  description = "Generated root/admin password — the day-one access for the ESXi image (the Linux images use ssh_keys instead)."
  value       = pnap_server.metal.password
  sensitive   = true
}

output "status" {
  description = "BMC provisioning status."
  value       = pnap_server.metal.status
}
