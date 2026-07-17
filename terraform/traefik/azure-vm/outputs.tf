output "instances" {
  description = "Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1)"
  value       = module.vm.instances
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443)"
  value = {
    (module.vm.instances[local.instance_key].name) = module.vm.private_ips[local.instance_key]
  }
}

output "public_ips" {
  description = "Map of instance names to their public IP addresses (empty string when enable_public_ip = false)"
  value = {
    (module.vm.instances[local.instance_key].name) = module.vm.public_ips[local.instance_key]
  }
}

output "principal_id" {
  description = "Principal ID of the VM's system-assigned managed identity (the azureVM provider's credential)"
  value       = module.vm.principal_ids[local.instance_key]
}
