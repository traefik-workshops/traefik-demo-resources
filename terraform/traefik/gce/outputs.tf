output "instances" {
  description = "Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1)"
  value = {
    (google_compute_instance.traefik.name) = {
      id         = google_compute_instance.traefik.id
      name       = google_compute_instance.traefik.name
      private_ip = google_compute_instance.traefik.network_interface[0].network_ip
      public_ip  = var.enable_public_ip ? google_compute_instance.traefik.network_interface[0].access_config[0].nat_ip : ""
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443)"
  value = {
    (google_compute_instance.traefik.name) = google_compute_instance.traefik.network_interface[0].network_ip
  }
}

output "public_ips" {
  description = "Map of instance names to their public IP addresses (empty string when enable_public_ip = false)"
  value = {
    (google_compute_instance.traefik.name) = var.enable_public_ip ? google_compute_instance.traefik.network_interface[0].access_config[0].nat_ip : ""
  }
}

output "service_account_email" {
  description = "Email of the service account attached to the VM (the gce provider's ADC credential)"
  value       = google_service_account.traefik.email
}
