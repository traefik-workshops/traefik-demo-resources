output "instances" {
  description = "Map of all echo server VMs with their details"
  value = {
    for key, vm in azurerm_linux_virtual_machine.whoami : key => {
      id         = vm.id
      name       = vm.name
      private_ip = vm.private_ip_address
      public_ip  = var.enable_public_ip ? azurerm_public_ip.whoami[key].ip_address : ""
    }
  }
}
