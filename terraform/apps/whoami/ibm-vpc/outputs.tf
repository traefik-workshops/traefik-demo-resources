output "instances" {
  description = "Map of all echo server instances with their details"
  value = {
    for key, vm in ibm_is_instance.whoami : key => {
      id         = vm.id
      name       = vm.name
      private_ip = vm.primary_network_interface[0].primary_ip[0].address
      public_ip  = var.enable_floating_ip ? ibm_is_floating_ip.whoami[key].address : ""
    }
  }
}
