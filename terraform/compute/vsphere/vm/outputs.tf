output "instances" {
  description = "Map of all VMs with their details (private_ip and public_ip are the SAME guest address reported by open-vm-tools — vSphere VMs have one primary IP and no cloud public-IP concept)."
  value = {
    for key, vm in vsphere_virtual_machine.vm : key => {
      id         = vm.id
      name       = vm.name
      private_ip = vm.default_ip_address
      public_ip  = vm.default_ip_address
    }
  }
}

output "private_ips" {
  description = "Map of instance keys to their guest IP addresses."
  value = {
    for key, vm in vsphere_virtual_machine.vm : key => vm.default_ip_address
  }
}

output "public_ips" {
  description = "Map of instance keys to their guest IP addresses — identical to private_ips (no public-IP concept on vSphere; kept for sibling-parity)."
  value = {
    for key, vm in vsphere_virtual_machine.vm : key => vm.default_ip_address
  }
}
