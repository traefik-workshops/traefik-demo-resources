variable "name" {
  type        = string
  description = "VPC name."
}

variable "cidr" {
  type        = string
  description = "VPC CIDR."
  default     = "10.0.0.0/16"
}

variable "vswitch_cidrs" {
  type        = list(string)
  description = "CIDR block per vswitch (one vswitch each, spread across the region's zones). Defaults carve two /24s out of the VPC CIDR."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "extra_ingress_ports" {
  type        = list(number)
  description = "Additional TCP ports to open on the demo security group from INSIDE the VPC only, beyond the default 80/443/8080/22 (those are open to any source). Default covers the Traefik Hub multicluster uplink entrypoint (:9443) on ECS/ECI spokes the parent cluster dials."
  default     = [9443]
}
