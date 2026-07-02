output "instances" {
  description = "Map of all echo server VMs with their details"
  value = {
    for key, vm in oci_core_instance.whoami : key => {
      id         = vm.id
      name       = vm.display_name
      private_ip = vm.private_ip
      public_ip  = var.enable_public_ip ? vm.public_ip : ""
    }
  }
}
