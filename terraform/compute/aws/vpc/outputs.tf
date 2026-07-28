output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnets IDs"
  value       = module.vpc.public_subnets
}

output "security_group_ids" {
  description = "Security group ID"
  value       = [aws_security_group.demo_sg.id]
}

output "private_route_table_ids" {
  description = "Private route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "public_route_table_ids" {
  description = "Public route table IDs"
  value       = module.vpc.public_route_table_ids
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks, index-aligned with private_subnet_ids. Plan-known (straight from the variable), so callers can pin instance addresses with cidrhost() and reference them before anything is applied."
  value       = var.private_subnets
}

output "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks, index-aligned with public_subnet_ids. Plan-known, same purpose as private_subnet_cidrs."
  value       = var.public_subnets
}

output "vpc_ipv6_cidr_block" {
  description = "The Amazon-provided /56 assigned to the VPC, or \"\" when `enable_ipv6 = false`. Lets a caller assert dual stack is actually on before asserting anything about IPv6 addressing."
  value       = try(module.vpc.vpc_ipv6_cidr_block, "")
}
