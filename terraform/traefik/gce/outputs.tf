output "instances" {
  description = "Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1)"
  value       = module.compute.instances
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443)"
  value       = module.compute.private_ips
}

output "public_ips" {
  description = "Map of instance names to their public IP addresses (empty string when enable_public_ip = false)"
  value       = module.compute.public_ips
}

output "service_account_email" {
  description = "Email of the service account attached to the VM (the gce provider's ADC credential)"
  value       = google_service_account.traefik.email
}
