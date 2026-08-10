output "instances" {
  description = "Map of all whoami VMs with their details. private_ip is the statically-PLANNED guest address (an input echoed back — Hyper-V has no plan-readable discovery; the provider reads live addresses from VMM's adapter view at poll time). No public-IP concept on-prem."
  value = {
    for key, inst in module.vm.instances : key => {
      id         = inst.id
      name       = inst.name
      private_ip = inst.private_ip
    }
  }
}
