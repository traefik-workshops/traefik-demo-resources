output "vpc_id" {
  description = "VPC ID"
  value       = alicloud_vpc.demo.id
}

output "vpc_name" {
  description = "VPC name"
  value       = alicloud_vpc.demo.vpc_name
}

output "vswitch_id" {
  description = "ID of the first vswitch (the convenience pick for single-vswitch workloads)"
  value       = alicloud_vswitch.demo[0].id
}

output "vswitch_ids" {
  description = "IDs of all vswitches (zone-spread — ACK control planes / node pools can consume the list directly)"
  value       = alicloud_vswitch.demo[*].id
}

output "security_group_id" {
  description = "Demo security group ID — attach it to the ECS instances / ECI container groups joining the vswitches (Alibaba security groups bind to workloads, not subnets)"
  value       = alicloud_security_group.demo.id
}

output "security_group_ids" {
  description = "Demo security group ID as a one-element list (mirrors compute/aws/vpc)"
  value       = [alicloud_security_group.demo.id]
}

output "vswitch_cidrs" {
  description = "CIDR block per vswitch, index-aligned with vswitch_ids. Plan-known (straight from the variable), so callers can pin instance addresses with cidrhost() and reference them before anything is applied."
  value       = var.vswitch_cidrs
}
