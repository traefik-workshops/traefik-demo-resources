output "container_group_id" {
  description = "ID of the Traefik ECI container group"
  value       = alicloud_eci_container_group.traefik.id
}

output "ip_address" {
  description = "Private vswitch IP of the Traefik container group (the parent dials https://<ip>:9443)"
  value       = alicloud_eci_container_group.traefik.intranet_ip
}

output "private_ips" {
  description = "Map of instance name to private IP (mirrors traefik/alibaba-ecs's consumption shape: values(...)[0])"
  value = {
    (alicloud_eci_container_group.traefik.container_group_name) = alicloud_eci_container_group.traefik.intranet_ip
  }
}

output "ram_role_name" {
  description = "Name of the RAM role the alibabaECI provider authenticates as (empty when enable_ram_role = false)"
  value       = var.enable_ram_role ? alicloud_ram_role.traefik[0].role_name : ""
}
