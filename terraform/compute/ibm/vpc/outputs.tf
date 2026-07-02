output "vpc_id" {
  description = "VPC ID"
  value       = ibm_is_vpc.demo.id
}

output "vpc_name" {
  description = "VPC name"
  value       = ibm_is_vpc.demo.name
}

output "subnet_id" {
  description = "ID of the first subnet (the convenience pick for single-subnet workloads)"
  value       = ibm_is_subnet.demo[0].id
}

output "subnet_ids" {
  description = "IDs of all subnets (zone-spread — compute/ibm/iks can consume the list directly)"
  value       = ibm_is_subnet.demo[*].id
}

output "security_group_id" {
  description = "Demo security group ID — attach it to the instances joining the subnets (IBM security groups bind to instances, not subnets)"
  value       = ibm_is_security_group.demo.id
}

output "security_group_ids" {
  description = "Demo security group ID as a one-element list (mirrors compute/aws/vpc)"
  value       = [ibm_is_security_group.demo.id]
}
