output "instances" {
  description = "Map of the created VMs with their details (keyed by VM name). private_ip and public_ip are the SAME statically-planned guest address — Hyper-V guests have one primary IP and no cloud public-IP concept (kept for sibling-parity)."
  value = {
    for key, inst in var.instances : key => {
      id         = terraform_data.vm[key].id
      name       = key
      private_ip = inst.ip_address
      public_ip  = inst.ip_address
    }
  }
}

output "private_ips" {
  description = "Map of instance names to their statically-planned guest IP addresses (known at PLAN time — the property that makes hub->child uplink addresses single-pass on Hyper-V)"
  value       = { for key, inst in var.instances : key => inst.ip_address }
}

output "public_ips" {
  description = "Map of instance names to their guest IP addresses — identical to private_ips (no public-IP concept on Hyper-V; kept for sibling-parity)"
  value       = { for key, inst in var.instances : key => inst.ip_address }
}
