output "container_groups" {
  description = "Map of all echo server container groups with their details"
  value = {
    for key, grp in azurerm_container_group.whoami : key => {
      id         = grp.id
      name       = grp.name
      private_ip = grp.ip_address
    }
  }
}
