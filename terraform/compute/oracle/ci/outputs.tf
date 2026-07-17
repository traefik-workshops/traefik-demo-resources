output "instances" {
  description = "Map of all container instances with their details (keyed by the var.instances key)."
  value = {
    for key, ci in oci_container_instances_container_instance.this : key => {
      id         = ci.id
      name       = ci.display_name
      private_ip = data.oci_core_vnic.this[key].private_ip_address
      public_ip  = data.oci_core_vnic.this[key].public_ip_address
    }
  }
}

output "private_ips" {
  description = "Map of instance key to private VNIC IP address."
  value = {
    for key, ci in oci_container_instances_container_instance.this : key => data.oci_core_vnic.this[key].private_ip_address
  }
}

output "public_ips" {
  description = "Map of instance key to public VNIC IP address (null unless enable_public_ip)."
  value = {
    for key, ci in oci_container_instances_container_instance.this : key => data.oci_core_vnic.this[key].public_ip_address
  }
}
