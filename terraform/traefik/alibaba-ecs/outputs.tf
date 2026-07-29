output "instances" {
  description = "Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1)"
  value       = module.compute.instances
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443)"
  value       = module.compute.private_ips
}

output "public_ips" {
  description = "Map of instance names to their public IP addresses (empty string when enable_public_ip = false)"
  value       = module.compute.public_ips
}

output "instance_id" {
  description = "ID of the Traefik ECS instance"
  value       = module.compute.instances[local.instance_key].id
}

output "ram_role_name" {
  description = "Name of the instance RAM role the alibabaECS provider authenticates as (empty when enable_ram_role = false)"
  value       = var.enable_ram_role ? alicloud_ram_role.traefik[0].role_name : ""
}
