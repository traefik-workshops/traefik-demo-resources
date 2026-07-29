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

variable "enable_nat_gateway" {
  type        = bool
  description = "Attach a shared NAT gateway (with a PayByTraffic EIP + one SNAT rule per vswitch) so vswitch workloads have OUTBOUND internet — required for ECS/ECI spokes to pull images from ghcr.io (an Alibaba VPC has no default egress). Egress only: no public inbound on the spokes. Off only when the vswitch already has another egress path."
  default     = true
}
