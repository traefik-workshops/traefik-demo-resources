output "instances" {
  description = "Map of all echo server VMs with their details (private_ip is the guest IP reported by open-vm-tools — vSphere VMs have one primary address, no cloud public-IP concept)"
  value = {
    for key, vm in vsphere_virtual_machine.whoami : key => {
      id         = vm.id
      name       = vm.name
      private_ip = vm.default_ip_address
    }
  }
}
