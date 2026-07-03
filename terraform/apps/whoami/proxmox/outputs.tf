output "instances" {
  description = "Map of all whoami guests with their details. For type=vm, private_ip is the QEMU-agent-reported guest IP; for type=lxc it is NULL — the container DHCPs inside and terraform never learns the address (the proxmox plugin discovers container IPs itself via the PVE API). No public-IP concept on-prem."
  value = merge(
    {
      for key, vm in proxmox_virtual_environment_vm.whoami : key => {
        id   = vm.id
        name = vm.name
        type = "vm"
        private_ip = [
          for idx, ifname in vm.network_interface_names :
          vm.ipv4_addresses[idx][0]
          if can(regex("^(eth|en)", ifname)) && length(vm.ipv4_addresses[idx]) > 0
        ][0]
      }
    },
    {
      for key, ct in proxmox_virtual_environment_container.whoami : key => {
        id         = ct.id
        name       = key
        type       = "lxc"
        private_ip = null
      }
    },
  )
}
