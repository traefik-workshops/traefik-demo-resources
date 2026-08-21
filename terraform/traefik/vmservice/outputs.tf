output "instances" {
  description = "Map of the Traefik VM with its details (keyed like traefik/vsphere-vm: <vm_name>-1). private_ip is status.network.primaryIP4 — the guest address the namespace network assigned, known only after apply."
  value = {
    (local.instance_key) = {
      name       = local.instance_key
      namespace  = var.namespace
      private_ip = data.external.guest.result.ip
      bios_uuid  = data.external.guest.result.bios_uuid
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their guest IP addresses (the parent dials https://<ip>:9443). Known only after apply — feed a parent that needs it at plan time through a variable filled between two applies."
  value       = { (local.instance_key) = data.external.guest.result.ip }
}

output "public_ips" {
  description = "Map of instance names to their guest IP addresses — identical to private_ips (no public-IP concept on vSphere; kept for sibling-parity)"
  value       = { (local.instance_key) = data.external.guest.result.ip }
}
