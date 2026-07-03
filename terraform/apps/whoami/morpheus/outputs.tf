output "instances" {
  description = "Map of all echo server instances with their details (private_ip is the primary connection IP Morpheus reports, connection_info[0] — on-prem there's no private/public distinction, the provider's ipModes resolve to the same address)"
  value = {
    for key, inst in hpe_morpheus_instance.whoami : key => {
      id         = inst.id
      name       = inst.name
      private_ip = try(inst.connection_info[0], null)
    }
  }
}
