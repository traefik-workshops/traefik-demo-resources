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

output "bootstrap_task_ids" {
  description = "Bootstrap shell-script task ids, by app. Only useful when enable_provisioning_workflow=false: the caller executes these itself via POST /api/tasks/{id}/execute with {\"job\":{\"targetType\":\"instance\",\"instances\":[<id>]}} — the ungated path on HPE VM Essentials."
  value       = { for k, v in hpe_morpheus_task_shell_script.bootstrap : k => v.id }
}
