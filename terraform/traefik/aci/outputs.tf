output "container_group_id" {
  description = "ID of the Traefik container group"
  value       = module.compute.instances[var.name].id
}

output "ip_address" {
  description = "Private vnet-injected IP of the Traefik container group (the parent dials https://<ip>:9443)"
  value       = module.compute.instances[var.name].private_ip
}

output "private_ips" {
  description = "Map of group name to private IP (mirrors traefik/azure-vm's consumption shape: values(...)[0])"
  value       = module.compute.private_ips
}

output "principal_id" {
  description = "Principal ID of the group's system-assigned managed identity (the aci provider's credential)"
  value       = module.compute.instances[var.name].principal_id
}
