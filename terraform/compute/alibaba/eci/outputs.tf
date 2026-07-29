output "instances" {
  description = "Map of all container groups keyed by name, with their details."
  value = {
    for key, group in alicloud_eci_container_group.this : key => {
      id         = group.id
      private_ip = group.intranet_ip
      public_ip  = group.internet_ip
    }
  }
}

output "private_ips" {
  description = "Map of container-group names to their private intranet IP (the address the parent dials in-VPC)."
  value = {
    for key, group in alicloud_eci_container_group.this : key => group.intranet_ip
  }
}

output "public_ips" {
  description = "Map of container-group names to their public internet IP (empty unless the group was assigned one)."
  value = {
    for key, group in alicloud_eci_container_group.this : key => group.internet_ip
  }
}
