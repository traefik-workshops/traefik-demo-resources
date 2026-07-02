output "instances" {
  description = "Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1)"
  value = {
    (ibm_is_instance.traefik.name) = {
      id         = ibm_is_instance.traefik.id
      name       = ibm_is_instance.traefik.name
      private_ip = ibm_is_instance.traefik.primary_network_interface[0].primary_ip[0].address
      public_ip  = var.enable_floating_ip ? ibm_is_floating_ip.traefik[0].address : ""
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443)"
  value = {
    (ibm_is_instance.traefik.name) = ibm_is_instance.traefik.primary_network_interface[0].primary_ip[0].address
  }
}

output "public_ips" {
  description = "Map of instance names to their floating IP addresses (empty string when enable_floating_ip = false)"
  value = {
    (ibm_is_instance.traefik.name) = var.enable_floating_ip ? ibm_is_floating_ip.traefik[0].address : ""
  }
}

output "instance_id" {
  description = "ID of the Traefik virtual server instance"
  value       = ibm_is_instance.traefik.id
}
