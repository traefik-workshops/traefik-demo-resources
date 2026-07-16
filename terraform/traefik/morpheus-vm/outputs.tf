output "instances" {
  description = "Map of the Traefik instance with its details (keyed like traefik/ec2: traefik-1). private_ip and public_ip are the SAME primary connection address (connection_info[0]) — on-prem Morpheus instances have one primary IP and no cloud public-IP concept (the provider's private/public ipModes both resolve to it)."
  value = {
    (hpe_morpheus_instance.traefik.name) = {
      id         = hpe_morpheus_instance.traefik.id
      name       = hpe_morpheus_instance.traefik.name
      private_ip = try(hpe_morpheus_instance.traefik.connection_info[0], null)
      public_ip  = try(hpe_morpheus_instance.traefik.connection_info[0], null)
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their primary IP addresses (the parent dials https://<ip>:9443)"
  value = {
    (hpe_morpheus_instance.traefik.name) = try(hpe_morpheus_instance.traefik.connection_info[0], null)
  }
}

output "public_ips" {
  description = "Map of instance names to their primary IP addresses — identical to private_ips (no public-IP concept on-prem; kept for sibling-parity)"
  value = {
    (hpe_morpheus_instance.traefik.name) = try(hpe_morpheus_instance.traefik.connection_info[0], null)
  }
}

output "bootstrap_task_ids" {
  description = "Bootstrap shell-script task ids, by app. Only useful when enable_provisioning_workflow=false: the caller executes these itself via POST /api/tasks/{id}/execute with {\"job\":{\"targetType\":\"instance\",\"instances\":[<id>]}} — the ungated path on HPE VM Essentials."
  value       = { bootstrap = hpe_morpheus_task_shell_script.bootstrap.id }
}
