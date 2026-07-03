output "instances" {
  description = "Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1). private_ip and public_ip are the SAME primary connection address — on-prem Morpheus instances have one primary IP and no cloud public-IP concept (the provider's private/public ipModes both resolve to it)."
  value = {
    (morpheus_mvm_instance.traefik.name) = {
      id         = morpheus_mvm_instance.traefik.id
      name       = morpheus_mvm_instance.traefik.name
      private_ip = morpheus_mvm_instance.traefik.primary_ip_address
      public_ip  = morpheus_mvm_instance.traefik.primary_ip_address
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their primary IP addresses (the parent dials https://<ip>:9443)"
  value = {
    (morpheus_mvm_instance.traefik.name) = morpheus_mvm_instance.traefik.primary_ip_address
  }
}

output "public_ips" {
  description = "Map of instance names to their primary IP addresses — identical to private_ips (no public-IP concept on-prem; kept for sibling-parity)"
  value = {
    (morpheus_mvm_instance.traefik.name) = morpheus_mvm_instance.traefik.primary_ip_address
  }
}
