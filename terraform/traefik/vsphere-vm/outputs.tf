output "instances" {
  description = "Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1). private_ip and public_ip are the SAME guest address — vSphere VMs have one primary IP and no cloud public-IP concept (the provider's private/public ipModes both resolve to it)."
  value       = module.compute.instances
}

output "private_ips" {
  description = "Map of instance names to their guest IP addresses (the parent dials https://<ip>:9443)"
  value       = module.compute.private_ips
}

output "public_ips" {
  description = "Map of instance names to their guest IP addresses — identical to private_ips (no public-IP concept on vSphere; kept for sibling-parity)"
  value       = module.compute.public_ips
}
