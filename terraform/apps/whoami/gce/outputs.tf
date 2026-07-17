output "instances" {
  description = "Map of all echo server VMs with their details"
  value       = module.compute.instances
}
