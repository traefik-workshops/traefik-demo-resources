output "instances" {
  description = "Map of instances keyed by instance name -> { id, name, private_ip, public_ip }"
  value = {
    for key, instance in alicloud_instance.ecs : key => {
      id         = instance.id
      name       = instance.instance_name
      private_ip = instance.private_ip
      public_ip  = var.enable_public_ip ? instance.public_ip : ""
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses"
  value = {
    for key, instance in alicloud_instance.ecs : key => instance.private_ip
  }
}

output "public_ips" {
  description = "Map of instance names to their public IP addresses (empty string when enable_public_ip = false)"
  value = {
    for key, instance in alicloud_instance.ecs : key => var.enable_public_ip ? instance.public_ip : ""
  }
}
