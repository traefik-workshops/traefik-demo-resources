variable "apps" {
  description = "Map of applications to deploy to Azure VMs. Each app can have multiple replicas. Same shape as apps/whoami/ec2: { name = { replicas, port, name, tags } }."
  type        = any
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group the VMs are created in"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
  default     = "eastus"
}

variable "vm_size" {
  description = "Azure VM size for all echo servers"
  type        = string
  default     = "Standard_B1s"
}

variable "common_tags" {
  description = "Common tags to apply to all VMs"
  type        = map(string)
  default     = {}
}

variable "create_vnet" {
  description = "Create a demo VNet (compute/azure/vnet) if subnet_id is not provided. Off by default — these VMs normally join an existing VNet."
  type        = bool
  default     = false
}

variable "subnet_id" {
  description = "ID of the existing subnet the VM NICs join"
  type        = string
  default     = ""

  validation {
    condition     = var.create_vnet || var.subnet_id != ""
    error_message = "subnet_id must be provided if create_vnet is false"
  }
}

variable "network_security_group_id" {
  description = "NSG ID to associate with the VM NICs. Empty = no NIC-level NSG (subnet-level NSG rules still apply)."
  type        = string
  default     = ""
}

variable "whoami_version" {
  description = "The Whoami version to install. Must be a real traefik/whoami image tag — they carry a `v` prefix (e.g. v1.11.0); a bare `1.11.0` is `manifest unknown` and the binary extraction silently fails."
  type        = string
  default     = "v1.11.0"
}

variable "admin_username" {
  description = "Admin username on the VMs (the cloud-init also creates the demo `traefiker` user)"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Admin password on the VMs. Default satisfies Azure's complexity rules; demo-grade only."
  type        = string
  default     = "TopSecretPassword1!"
  sensitive   = true
}

variable "enable_public_ip" {
  description = "Attach a public IP to each VM. Off by default — the Traefik child dials private IPs (ipMode=private)."
  type        = bool
  default     = false
}
