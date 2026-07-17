output "instances" {
  description = "Map of all instances keyed by \"<app>-<replica>\" with their details. private_ip and public_ip are the SAME primary connection address (connection_info[0]) — on-prem Morpheus instances have one primary IP and no cloud public-IP concept (the provider's private/public ipModes both resolve to it)."
  value = {
    for key, inst in hpe_morpheus_instance.this : key => {
      id         = inst.id
      name       = inst.name
      private_ip = try(inst.connection_info[0], null)
      public_ip  = try(inst.connection_info[0], null)
    }
  }
}

output "private_ips" {
  description = "Map of instance keys to their primary IP addresses (the parent dials this address)"
  value = {
    for key, inst in hpe_morpheus_instance.this : key => try(inst.connection_info[0], null)
  }
}

output "public_ips" {
  description = "Map of instance keys to their primary IP addresses — identical to private_ips (no public-IP concept on-prem; kept for sibling-parity with compute/aws/ec2)"
  value = {
    for key, inst in hpe_morpheus_instance.this : key => try(inst.connection_info[0], null)
  }
}

output "bootstrap_task_ids" {
  description = "Bootstrap shell-script task ids, by app key. Only useful when enable_provisioning_workflow=false: the caller executes these itself via POST /api/tasks/{id}/execute with {\"job\":{\"targetType\":\"instance\",\"instances\":[<id>]}} — the ungated path on HPE VM Essentials."
  value       = { for k, v in hpe_morpheus_task_shell_script.bootstrap : k => v.id }
}
