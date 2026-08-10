output "instances" {
  description = "Map of the Traefik VM with its details (keyed like traefik/ec2: <vm_name>-1). private_ip and public_ip are the SAME statically-planned guest address — Hyper-V guests have one primary IP and no cloud public-IP concept."
  value       = module.vm.instances
}

output "private_ips" {
  description = "Map of instance names to their static guest IP addresses (the parent dials https://<ip>:9443). PLAN-KNOWN — the hub's children map wires in one pass, no PENDING."
  value       = module.vm.private_ips
}

output "public_ips" {
  description = "Map of instance names to their guest IP addresses — identical to private_ips (no public-IP concept on Hyper-V; kept for sibling-parity)"
  value       = module.vm.public_ips
}

output "uplink_address" {
  description = "The https://<static-ip>:9443 address the hub's multicluster children map dials — plan-known, because the address is an input."
  value       = "https://${split("/", var.ip_address)[0]}:9443"
}
