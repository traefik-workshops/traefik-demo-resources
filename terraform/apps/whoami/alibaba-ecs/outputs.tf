output "instances" {
  description = "Map of all echo server instances with their details"
  value       = merge([for app, compute in module.compute : compute.instances]...)
}
