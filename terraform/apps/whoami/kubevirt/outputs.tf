output "instances" {
  description = "Map of whoami guests. No private_ip, unlike the cloud siblings: the address a caller would want belongs to the guest's virt-launcher pod (or its VMI status) and is not known to terraform at apply time — the kubevirt provider resolves it itself, every refresh, which is the whole point of discovering a VM as a VM. `hostname` is what the response body echoes as `Hostname:`."
  value = {
    for k, inst in local.instances_map : k => {
      name      = inst.name
      namespace = var.namespace
      hostname  = k
    }
  }
}

output "vm_names" {
  description = "VirtualMachine object names, one per replica — the same strings as the guests' hostnames. Useful as a `kubectl wait`/readiness-gate trigger."
  value       = keys(local.instances_map)
}

output "service_names" {
  description = "Traefik service names the guests' labels declare (the `traefik.http.services.<name>` segment), so a caller can point a file router at a service it knows exists. Because every replica of an app carries the SAME labels and the provider merges same-named services, each of these is ONE service with `replicas` servers behind it."
  value = distinct(flatten([
    for inst in local.instances : [
      for k, v in inst.traefik_labels :
      split(".", k)[3] if length(split(".", k)) > 3 && startswith(k, "traefik.http.services.")
    ]
  ]))
}
