output "instances" {
  description = "Map of VM key -> details (keyed like the input: <app>-<replica>)."
  value = {
    for key, vm in google_compute_instance.vm : key => {
      id         = vm.id
      name       = vm.name
      private_ip = vm.network_interface[0].network_ip
      public_ip  = var.enable_public_ip ? vm.network_interface[0].access_config[0].nat_ip : ""
    }
  }
}

output "private_ips" {
  description = "Map of VM key -> private IP address."
  value = {
    for key, vm in google_compute_instance.vm : key => vm.network_interface[0].network_ip
  }
}

output "public_ips" {
  description = "Map of VM key -> public IP address (empty string when enable_public_ip = false)."
  value = {
    for key, vm in google_compute_instance.vm : key => var.enable_public_ip ? vm.network_interface[0].access_config[0].nat_ip : ""
  }
}
