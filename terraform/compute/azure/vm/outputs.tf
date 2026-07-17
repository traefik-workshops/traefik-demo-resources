output "instances" {
  description = "Map of instance key -> VM details (id, name, private_ip, public_ip)"
  value = {
    for key, vm in azurerm_linux_virtual_machine.vm : key => {
      id         = vm.id
      name       = vm.name
      private_ip = vm.private_ip_address
      public_ip  = var.enable_public_ip ? azurerm_public_ip.vm[key].ip_address : ""
    }
  }
}

output "private_ips" {
  description = "Map of instance key -> private IP (pinned instances return their static address)"
  value = {
    for key, vm in azurerm_linux_virtual_machine.vm : key => vm.private_ip_address
  }
}

output "public_ips" {
  description = "Map of instance key -> public IP (empty string when enable_public_ip = false)"
  value = {
    for key, vm in azurerm_linux_virtual_machine.vm : key => (
      var.enable_public_ip ? azurerm_public_ip.vm[key].ip_address : ""
    )
  }
}

output "principal_ids" {
  description = "Map of instance key -> managed-identity principal id (null when identity_type = null). The Traefik caller grants this principal Reader for the azureVM provider's discovery scope."
  value = {
    for key, vm in azurerm_linux_virtual_machine.vm : key => try(vm.identity[0].principal_id, null)
  }
}
