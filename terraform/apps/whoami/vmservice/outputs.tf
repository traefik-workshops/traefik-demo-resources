output "instances" {
  description = "Map of all whoami VMs with their details. private_ip is status.network.primaryIP4 — the guest address vm-operator reports, the same one VMware Tools reports and the Hub vsphere provider dials. bios_uuid is what the tag attach located the vCenter object by."
  value = {
    for key, inst in local.instances_map : key => {
      name       = inst.name
      namespace  = var.namespace
      private_ip = data.external.guest[key].result.ip
      bios_uuid  = data.external.guest[key].result.bios_uuid
    }
  }
}

output "private_ips" {
  description = "Map of instance keys to their guest IP addresses (known only after apply — vm-operator assigns them)."
  value       = { for key, inst in local.instances_map : key => data.external.guest[key].result.ip }
}

output "vm_names" {
  description = "VirtualMachine object names, one per replica — also the guests' hostnames and their vCenter inventory names."
  value       = keys(local.instances_map)
}
