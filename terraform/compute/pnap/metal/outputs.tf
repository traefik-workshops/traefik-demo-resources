output "id" {
  description = "BMC server ID."
  value       = pnap_server.metal.id
}

output "public_ip" {
  description = "Primary public IP — where the operator (and the demo's terraform) reaches the hypervisor API (Proxmox :8006, ESXi/VCSA :443, Morpheus manager). This is the HOST's own address; with a multi-address block the rest are free for guests (see public_ip_range)."
  # public_ip_addresses is a SET — sort() for a deterministic pick of the first. When the
  # server carries a block bigger than the default /30, BMC reports the assignment as a
  # RANGE STRING ("192.0.2.218 - 192.0.2.222") rather than one entry per address, and the
  # host takes the first of it — so trim to the low address instead of handing callers a
  # range where they expect an IP.
  value = trimspace(try(split("-", sort(pnap_server.metal.public_ip_addresses)[0])[0], ""))
}

output "public_ip_range" {
  description = "The raw public address assignment. A single IP on the default /30; a \"first - last\" RANGE when a larger block is attached (var.ip_block_id) — the addresses after public_ip are free for guests."
  value       = try(sort(pnap_server.metal.public_ip_addresses)[0], "")
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
