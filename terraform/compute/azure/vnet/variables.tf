variable "name" {
  type        = string
  description = "VNet name."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group the VNet (and NSG) are created in."
}

variable "location" {
  type        = string
  description = "Azure location."
  default     = "eastus"
}

variable "cidr" {
  type        = string
  description = "VNet CIDR."
  default     = "10.0.0.0/16"
}

variable "vm_subnet_cidr" {
  type        = string
  description = "CIDR block for the VM subnet. Default carves a /24 out of the VNet CIDR."
  default     = "10.0.1.0/24"
}

variable "aci_subnet_cidr" {
  type        = string
  description = "CIDR block for the ACI subnet (delegated to Microsoft.ContainerInstance — only container groups can live here). Default carves a /24 out of the VNet CIDR."
  default     = "10.0.2.0/24"
}

variable "extra_ingress_ports" {
  type        = list(number)
  description = "Additional TCP ports to open on the demo NSG (from any source), beyond the default 80/443/8080/22. Used for the Traefik Hub multicluster uplink entrypoint (:9443) on VM/ACI spokes the parent cluster dials."
  default     = []
}
