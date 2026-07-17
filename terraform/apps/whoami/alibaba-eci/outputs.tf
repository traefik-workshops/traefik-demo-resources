output "container_groups" {
  description = "Map of all echo server container groups with their details"
  value = {
    for key, inst in module.compute.instances : key => {
      id         = inst.id
      name       = key
      private_ip = inst.private_ip
    }
  }
}
