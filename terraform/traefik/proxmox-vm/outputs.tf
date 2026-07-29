output "instances" {
  description = "Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1). private_ip and public_ip are the SAME guest address — Proxmox guests have one primary IP and no cloud public-IP concept."
  value       = module.vm.instances
}

output "private_ips" {
  description = "Map of instance names to their guest IP addresses (the parent dials https://<ip>:9443)"
  value       = module.vm.private_ips
}

output "public_ips" {
  description = "Map of instance names to their guest IP addresses — identical to private_ips (no public-IP concept on Proxmox; kept for sibling-parity)"
  value       = module.vm.public_ips
}
