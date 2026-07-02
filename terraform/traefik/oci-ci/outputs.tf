output "container_instance_id" {
  description = "OCID of the Traefik container instance"
  value       = oci_container_instances_container_instance.traefik.id
}

output "ip_address" {
  description = "Private VNIC IP of the Traefik container instance (the parent dials https://<ip>:9443)"
  value       = data.oci_core_vnic.traefik.private_ip_address
}

output "private_ips" {
  description = "Map of instance name to private IP (mirrors traefik/oci-vm's consumption shape: values(...)[0])"
  value = {
    (oci_container_instances_container_instance.traefik.display_name) = data.oci_core_vnic.traefik.private_ip_address
  }
}
