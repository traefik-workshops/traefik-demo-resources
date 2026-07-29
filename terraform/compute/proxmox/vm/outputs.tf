output "instances" {
  description = "Map of the created VMs with their details (keyed by VM name). private_ip and public_ip are the SAME guest address — Proxmox guests have one primary IP and no cloud public-IP concept."
  value = {
    for key, vm in proxmox_virtual_environment_vm.this : key => {
      id         = vm.id
      name       = vm.name
      private_ip = local.private_ips[key]
      public_ip  = local.private_ips[key]
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their QEMU-agent-reported guest IP addresses"
  value       = local.private_ips
}

output "public_ips" {
  description = "Map of instance names to their guest IP addresses — identical to private_ips (no public-IP concept on Proxmox; kept for sibling-parity)"
  value       = local.private_ips
}
