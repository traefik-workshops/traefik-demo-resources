output "instances" {
  description = "Map of all container groups with their details, keyed by group name"
  value = {
    for key, grp in azurerm_container_group.this : key => {
      id         = grp.id
      name       = grp.name
      private_ip = grp.ip_address
      # ACI exposes a single ip_address; there is no separate public attribute.
      # A Public group's ip_address is its public IP, a Private group's is private.
      public_ip    = var.ip_address_type == "Public" ? grp.ip_address : null
      principal_id = var.enable_system_identity ? grp.identity[0].principal_id : null
    }
  }
}

output "private_ips" {
  description = "Map of group name to private (vnet-injected) IP address"
  value = {
    for key, grp in azurerm_container_group.this : key => grp.ip_address
  }
}

output "public_ips" {
  description = "Map of group name to public IP address (null for Private ip_address_type)"
  value = {
    for key, grp in azurerm_container_group.this : key => (var.ip_address_type == "Public" ? grp.ip_address : null)
  }
}
