output "container_instances" {
  description = "Map of all echo server container instances with their details"
  value = {
    for key, ci in oci_container_instances_container_instance.whoami : key => {
      id         = ci.id
      name       = ci.display_name
      private_ip = data.oci_core_vnic.whoami[key].private_ip_address
    }
  }
}
