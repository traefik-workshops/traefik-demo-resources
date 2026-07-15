output "private_ip" {
  description = "The gateway container's guest IP (the pinned ip_address, minus its /prefix). Known at PLAN time — this is the address the hub dials for the multicluster uplink."
  value       = split("/", var.ip_address)[0]
}

output "uplink_address" {
  description = "Ready-made multicluster child address for the hub's children map, e.g. https://10.10.10.50:9443. The uplink serves Traefik's default self-signed cert, so the hub dials it with serversTransport.insecureSkipVerify."
  value       = "https://${split("/", var.ip_address)[0]}:${try([for p in values(var.custom_ports) : p.port if try(p.uplink, false)][0], 9443)}"
}

output "container_id" {
  description = "PVE id of the gateway container."
  value       = proxmox_virtual_environment_container.traefik.id
}

output "instances" {
  description = "Gateway container details, shaped like the sibling gateway modules' outputs."
  value = {
    (var.container_name) = {
      id         = proxmox_virtual_environment_container.traefik.id
      name       = var.container_name
      type       = "lxc"
      private_ip = split("/", var.ip_address)[0]
    }
  }
}

output "image_full" {
  description = "The image the Hub binary was extracted from — should match every other gateway in the mesh (a child on a different Hub version cannot join the uplink)."
  value       = module.config.image_full
}
