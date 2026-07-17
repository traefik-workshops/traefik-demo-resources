output "instances" {
  description = "Map of all whoami guests with their details. For type=vm, private_ip is the QEMU-agent-reported guest IP; for type=lxc it is NULL — a container has no guest agent, so its DHCP lease is invisible to terraform. That is not a gap to work around: the proxmox plugin discovers container IPs itself via the PVE API, which is how the LXC legs get routed. No public-IP concept on-prem."
  value = merge(
    {
      for key, inst in module.vm.instances : key => {
        id         = inst.id
        name       = inst.name
        type       = "vm"
        private_ip = inst.private_ip
      }
    },
    {
      for key, inst in module.lxc.instances : key => {
        id         = inst.id
        name       = key
        type       = "lxc"
        private_ip = null
      }
    },
  )
}
