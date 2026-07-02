output "instances" {
  description = "Map of all echo server VMs with their details"
  value = {
    for key, vm in google_compute_instance.whoami : key => {
      id         = vm.id
      name       = vm.name
      private_ip = vm.network_interface[0].network_ip
      public_ip  = var.enable_public_ip ? vm.network_interface[0].access_config[0].nat_ip : ""
    }
  }
}
