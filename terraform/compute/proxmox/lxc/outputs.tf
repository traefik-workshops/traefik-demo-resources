output "instances" {
  description = "Map of the created containers with their details (keyed by container name). id is the PVE container id (the callers pct-exec against it). private_ip/public_ip are the pinned static IP for statically-addressed containers, or null for DHCP ones (no guest agent — discovered via the PVE API)."
  value = {
    for key, ct in proxmox_virtual_environment_container.this : key => {
      id         = ct.id
      name       = key
      private_ip = local.private_ips[key]
      public_ip  = local.private_ips[key]
    }
  }
}

output "private_ips" {
  description = "Map of container names to their pinned static IP (minus the /prefix), or null for DHCP containers."
  value       = local.private_ips
}

output "public_ips" {
  description = "Map of container names to their pinned static IP — identical to private_ips (no public-IP concept on Proxmox; kept for sibling-parity)."
  value       = local.private_ips
}
