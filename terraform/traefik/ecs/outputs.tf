output "services" {
  description = "Map of ECS services with their details"
  value       = module.ecs.services
}

output "nlb_dns_names" {
  description = "Map of service keys to their NLB DNS name (the parent dials https://<dns>:<nlb_port>)."
  value       = module.ecs.nlb_dns_names
}
