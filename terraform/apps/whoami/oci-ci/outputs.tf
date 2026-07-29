output "container_instances" {
  description = "Map of all echo server container instances with their details"
  value = {
    for key, inst in module.ci.instances : key => {
      id         = inst.id
      name       = inst.name
      private_ip = inst.private_ip
    }
  }
}
