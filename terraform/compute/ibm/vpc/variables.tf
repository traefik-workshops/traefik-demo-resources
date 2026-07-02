variable "name" {
  type        = string
  description = "VPC name."
}

variable "region" {
  type        = string
  description = "IBM Cloud region the VPC lands in (zone lookup). Must match the region the ibm provider is configured with."
}

variable "cidr" {
  type        = string
  description = "VPC CIDR the subnet prefixes are carved out of. Used as the source range for the intra-VPC extra_ingress_ports rules."
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  type        = list(string)
  description = "CIDR block per subnet (one subnet each, spread across the region's zones via manual address prefixes). Defaults carve two /24s out of the VPC CIDR."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "extra_ingress_ports" {
  type        = list(number)
  description = "Additional TCP ports to open on the demo security group from INSIDE the VPC only, beyond the default 80/443/8080/22 (those are open to any source). Default covers the Traefik Hub multicluster uplink entrypoint (:9443) on VM spokes the parent cluster dials."
  default     = [9443]
}

variable "resource_group_id" {
  type        = string
  description = "Resource group ID the VPC resources land in. Empty = the account's default resource group."
  default     = ""
}
