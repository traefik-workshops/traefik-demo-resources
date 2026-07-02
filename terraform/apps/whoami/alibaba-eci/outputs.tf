output "container_groups" {
  description = "Map of all echo server container groups with their details"
  value = {
    for key, grp in alicloud_eci_container_group.whoami : key => {
      id         = grp.id
      name       = grp.container_group_name
      private_ip = grp.intranet_ip
    }
  }
}
