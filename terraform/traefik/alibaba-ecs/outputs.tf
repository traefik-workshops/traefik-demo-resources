output "instances" {
  description = "Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1)"
  value = {
    (alicloud_instance.traefik.instance_name) = {
      id         = alicloud_instance.traefik.id
      name       = alicloud_instance.traefik.instance_name
      private_ip = alicloud_instance.traefik.private_ip
      public_ip  = var.enable_public_ip ? alicloud_instance.traefik.public_ip : ""
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443)"
  value = {
    (alicloud_instance.traefik.instance_name) = alicloud_instance.traefik.private_ip
  }
}

output "public_ips" {
  description = "Map of instance names to their public IP addresses (empty string when enable_public_ip = false)"
  value = {
    (alicloud_instance.traefik.instance_name) = var.enable_public_ip ? alicloud_instance.traefik.public_ip : ""
  }
}

output "instance_id" {
  description = "ID of the Traefik ECS instance"
  value       = alicloud_instance.traefik.id
}

output "ram_role_name" {
  description = "Name of the instance RAM role the alibabaECS provider authenticates as (empty when enable_ram_role = false)"
  value       = var.enable_ram_role ? alicloud_ram_role.traefik[0].role_name : ""
}
