output "instances" {
  description = "Map of all echo server VMs with their details"
  value = {
    for item in flatten([
      for app_name, mod in module.compute : [
        for key, inst in mod.instances : {
          key        = key
          id         = inst.id
          name       = inst.name
          private_ip = inst.private_ip
          public_ip  = var.enable_public_ip ? inst.public_ip : ""
        }
      ]
      ]) : item.key => {
      id         = item.id
      name       = item.name
      private_ip = item.private_ip
      public_ip  = item.public_ip
    }
  }
}
