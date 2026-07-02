output "instances" {
  description = "Map of all echo server instances with their details"
  value = {
    for key, vm in alicloud_instance.whoami : key => {
      id         = vm.id
      name       = vm.instance_name
      private_ip = vm.private_ip
      public_ip  = var.enable_public_ip ? vm.public_ip : ""
    }
  }
}
