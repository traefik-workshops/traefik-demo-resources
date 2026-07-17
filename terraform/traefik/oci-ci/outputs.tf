output "container_instance_id" {
  description = "OCID of the Traefik container instance"
  value       = module.ci.instances[var.name].id
}

output "ip_address" {
  description = "Private VNIC IP of the Traefik container instance (the parent dials https://<ip>:9443)"
  value       = module.ci.private_ips[var.name]
}

output "private_ips" {
  description = "Map of instance name to private IP (mirrors traefik/oci-vm's consumption shape: values(...)[0])"
  value       = module.ci.private_ips
}
