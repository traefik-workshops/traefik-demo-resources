output "instances" {
  description = "Map of all whoami guests with their details. For type=vm, private_ip is the QEMU-agent-reported guest IP. For type=lxc it is the PINNED ip_address when the app sets one, else NULL — a container has no guest agent, so a DHCP lease is invisible to terraform (only the proxmox plugin sees it, via the PVE API). Pin ip_address on an lxc app when something must route to it by address. No public-IP concept on-prem."
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
        id   = ct.id
        name = key
        type = "lxc"
        # The pinned address (ip_address minus its /prefix) when the app set one; null on
        # DHCP, where the lease is genuinely unknowable to terraform (no guest agent).
        private_ip = local.instances_map[key].ip_address != "" ? split("/", local.instances_map[key].ip_address)[0] : null
      }
    },
  )
}
