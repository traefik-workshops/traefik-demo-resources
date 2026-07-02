output "instances" {
  description = "Map of the Traefik VM with its details (keyed like traefik/ec2: traefik-1)"
  value = {
    (azurerm_linux_virtual_machine.traefik.name) = {
      id         = azurerm_linux_virtual_machine.traefik.id
      name       = azurerm_linux_virtual_machine.traefik.name
      private_ip = azurerm_linux_virtual_machine.traefik.private_ip_address
      public_ip  = var.enable_public_ip ? azurerm_public_ip.traefik[0].ip_address : ""
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their private IP addresses (the parent dials https://<private-ip>:9443)"
  value = {
    (azurerm_linux_virtual_machine.traefik.name) = azurerm_linux_virtual_machine.traefik.private_ip_address
  }
}

output "public_ips" {
  description = "Map of instance names to their public IP addresses (empty string when enable_public_ip = false)"
  value = {
    (azurerm_linux_virtual_machine.traefik.name) = var.enable_public_ip ? azurerm_public_ip.traefik[0].ip_address : ""
  }
}

output "principal_id" {
  description = "Principal ID of the VM's system-assigned managed identity (the azureVM provider's credential)"
  value       = azurerm_linux_virtual_machine.traefik.identity[0].principal_id
}
