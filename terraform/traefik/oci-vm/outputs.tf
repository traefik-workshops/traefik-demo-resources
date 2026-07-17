output "instances" {
  description = "Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1)"
  value = {
    for key, instance in module.compute.instances : key => {
      id         = instance.id
      name       = instance.name
      private_ip = instance.private_ip
      public_ip  = var.enable_public_ip ? instance.public_ip : ""
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443)"
  value       = module.compute.private_ips
}

output "public_ips" {
  description = "Map of instance names to their public IP addresses (empty string when enable_public_ip = false)"
  value = {
    for key, ip in module.compute.public_ips : key => var.enable_public_ip ? ip : ""
  }
}

output "instance_id" {
  description = "OCID of the Traefik VM (the member security/oci-instance-principal's dynamic group matches by compartment)"
  value       = one(values(module.compute.instances)).id
}
