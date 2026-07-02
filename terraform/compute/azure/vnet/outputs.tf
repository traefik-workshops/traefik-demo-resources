output "vnet_id" {
  description = "VNet ID"
  value       = azurerm_virtual_network.demo.id
}

output "vnet_name" {
  description = "VNet name"
  value       = azurerm_virtual_network.demo.name
}

output "vm_subnet_id" {
  description = "ID of the subnet for VMs"
  value       = azurerm_subnet.vms.id
}

output "aci_subnet_id" {
  description = "ID of the subnet delegated to Microsoft.ContainerInstance (for ACI container groups)"
  value       = azurerm_subnet.aci.id
}

output "network_security_group_id" {
  description = "Demo NSG ID"
  value       = azurerm_network_security_group.demo.id
}

output "security_group_ids" {
  description = "Demo NSG ID as a one-element list (mirrors compute/aws/vpc)"
  value       = [azurerm_network_security_group.demo.id]
}
