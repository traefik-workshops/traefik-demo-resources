output "instances" {
  description = "Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1)"
  value = {
    (oci_core_instance.traefik.display_name) = {
      id         = oci_core_instance.traefik.id
      name       = oci_core_instance.traefik.display_name
      private_ip = oci_core_instance.traefik.private_ip
      public_ip  = var.enable_public_ip ? oci_core_instance.traefik.public_ip : ""
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443)"
  value = {
    (oci_core_instance.traefik.display_name) = oci_core_instance.traefik.private_ip
  }
}

output "public_ips" {
  description = "Map of instance names to their public IP addresses (empty string when enable_public_ip = false)"
  value = {
    (oci_core_instance.traefik.display_name) = var.enable_public_ip ? oci_core_instance.traefik.public_ip : ""
  }
}

output "instance_id" {
  description = "OCID of the Traefik VM (the member security/oci-instance-principal's dynamic group matches by compartment)"
  value       = oci_core_instance.traefik.id
}
