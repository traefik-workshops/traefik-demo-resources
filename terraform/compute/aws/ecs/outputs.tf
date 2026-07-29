output "services" {
  description = "Map of all ECS services with their details"
  value = {
    for key, service in aws_ecs_service.service : key => {
      id                  = service.id
      name                = service.name
      cluster_name        = local.services_map[key].cluster_name
      app_name            = local.services_map[key].app_name
      replicas            = local.services_map[key].replicas
      task_definition_arn = aws_ecs_task_definition.service[key].arn
    }
  }
}

output "vpc_id" {
  description = "VPC ID the ECS services run in (created VPC, or the provided vpc_id)."
  value       = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
}

output "nlb_dns_names" {
  description = "Map of service keys to their NLB DNS name (only services with nlb_port set). The parent cluster dials https://<dns>:<nlb_port>."
  value       = { for k, lb in aws_lb.nlb : k => lb.dns_name }
}
