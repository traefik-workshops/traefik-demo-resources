# No `instances` map here, unlike every other whoami sibling: the containers are not
# terraform resources (see main.tf), so there is no id or private_ip to report. What the
# caller needs is the provisioning fragment and the names to assert on.

output "runcmd" {
  description = "Cloud-init runcmd blocks that start the containers. Feed straight into the Traefik child's `extra_runcmd` — the child must be the gateway on the SAME VM, since discovery is over the local Docker socket."
  value       = [local.runcmd]
}

output "container_names" {
  description = "Container names as they will appear in `docker ps` — the WHOAMI_NAME each echoes is the app's `name`, without the replica suffix."
  value       = [for c in local.containers : c.name]
}

output "service_names" {
  description = "Traefik service names the containers' labels declare (the `traefik.http.services.<name>` segment), so a caller can point a file router at a service it knows exists."
  value = distinct(flatten([
    for c in local.containers : [
      for k, v in c.labels :
      split(".", k)[3] if length(split(".", k)) > 3 && startswith(k, "traefik.http.services.")
    ]
  ]))
}
