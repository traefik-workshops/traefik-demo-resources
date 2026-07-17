output "instances" {
  description = "Map of instance keys to their details (id, name, private_ip, public_ip)."
  value = {
    for key, instance in oci_core_instance.vm : key => {
      id         = instance.id
      name       = instance.display_name
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
    }
  }
}

output "private_ips" {
  description = "Map of instance keys to private IP addresses."
  value = {
    for key, instance in oci_core_instance.vm : key => instance.private_ip
  }
}

output "public_ips" {
  description = "Map of instance keys to public IP addresses (empty string when no public IP is assigned)."
  value = {
    for key, instance in oci_core_instance.vm : key => instance.public_ip
  }
}
