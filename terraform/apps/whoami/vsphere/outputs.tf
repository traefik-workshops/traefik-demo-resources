output "instances" {
  description = "Map of all echo server VMs with their details (private_ip is the guest IP reported by open-vm-tools — vSphere VMs have one primary address, no cloud public-IP concept)"
  value = {
    for key, inst in module.compute.instances : key => {
      id         = inst.id
      name       = inst.name
      private_ip = inst.private_ip
    }
  }
}

output "private_ips" {
  description = "Instance key -> guest IP, the shape the other whoami fleets expose (on vSphere the guest's one primary address)."
  value       = { for key, inst in module.compute.instances : key => inst.private_ip }
}
