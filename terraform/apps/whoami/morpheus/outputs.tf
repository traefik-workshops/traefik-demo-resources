output "instances" {
  description = "Map of all echo server instances with their details (private_ip is the primary connection IP Morpheus reports — on-prem there's no private/public distinction, the provider's ipModes resolve to the same address)"
  value = {
    for key, inst in morpheus_mvm_instance.whoami : key => {
      id         = inst.id
      name       = inst.name
      private_ip = inst.primary_ip_address
    }
  }
}
