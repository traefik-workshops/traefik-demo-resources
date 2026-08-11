output "vm_name" {
  description = "The recording VM's name."
  value       = azurerm_linux_virtual_machine.desktop.name
}

output "vm_id" {
  description = "The recording VM's resource id."
  value       = azurerm_linux_virtual_machine.desktop.id
}

output "public_ip" {
  description = "Public IP (empty when enable_public_ip = false)."
  value       = var.enable_public_ip ? azurerm_public_ip.desktop[0].ip_address : ""
}

output "private_ip" {
  description = "Private IP on the subnet."
  value       = azurerm_linux_virtual_machine.desktop.private_ip_address
}

output "rdp_endpoint" {
  description = "host:3389 for xfreerdp/RDP (watch-only; capture happens on the VM)."
  value       = var.enable_public_ip ? "${azurerm_public_ip.desktop[0].ip_address}:3389" : ""
}

output "ssh_endpoint" {
  description = "user@host:22 for SSH (the primary agent driver)."
  value       = var.enable_public_ip ? "${var.admin_username}@${azurerm_public_ip.desktop[0].ip_address}:22" : ""
}

output "principal_id" {
  description = "Principal ID of the VM's system-assigned managed identity."
  value       = azurerm_linux_virtual_machine.desktop.identity[0].principal_id
}
