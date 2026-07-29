variable "apps" {
  description = "Map of applications to deploy as Azure Linux VMs, each with N replicas. Mirrors compute/aws/ec2's apps map (key -> { replicas, tags }). The instance key is \"<app>-<replica>\" — the VM, its NIC, and its optional public IP are all named off that key."
  type = map(object({
    replicas = optional(number, 1)
    tags     = optional(map(string), {}) # Pre-merged, opaque discovery/role tags (dotted traefik.* keys, etc.)
  }))
}

variable "replica_start_index" {
  description = "Starting index for replica numbering (Default: 1)"
  type        = number
  default     = 1
}

variable "resource_group_name" {
  description = "Resource group the VMs (and their NICs/public IPs) are created in"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
  default     = "eastus"
}

variable "vm_size" {
  description = "Azure VM size for every instance"
  type        = string
  default     = "Standard_B2s"
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

variable "common_tags" {
  description = "Common tags applied to every VM (merged under each app's own tags, which win on collision)"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "subnet_id" {
  description = "ID of the existing subnet every VM NIC joins"
  type        = string
}

variable "network_security_group_id" {
  description = "NSG ID to associate with the VM NICs (used only when enable_network_security_group = true; may be a same-run resource attribute). Subnet-level NSG rules still apply either way."
  type        = string
  default     = ""
}

variable "enable_network_security_group" {
  description = "Associate network_security_group_id with the VM NICs. A separate config-known toggle because for_each cannot depend on the id when it is created in the same run."
  type        = bool
  default     = false
}

variable "enable_public_ip" {
  description = "Attach a Standard/Static public IP to each VM."
  type        = bool
  default     = false
}

variable "private_ips" {
  description = "Fixed private IPs, one per instance index (instance idx N gets private_ips[N]; extra instances fall back to Dynamic/DHCP). Each address must sit in subnet_id's CIDR outside Azure's reserved first-4/last-1 hosts. Pinning makes the address plan-known AND stable across VM recreation — a hub dialing this child never goes stale."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Identity
# -----------------------------------------------------------------------------

variable "identity_type" {
  description = "Managed-identity type on the VMs (e.g. \"SystemAssigned\"). null = no identity block. The Traefik gateway passes \"SystemAssigned\" so DefaultAzureCredential inside the container resolves it via IMDS for the azureVM provider; the whoami backends leave it null."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Cloud-init
# -----------------------------------------------------------------------------

variable "user_data" {
  description = "Map of instance key (\"<app>-<replica>\") -> already-rendered cloud-init/custom_data. Opaque to this module: base64-encoded straight onto each VM's custom_data. The caller owns all cloud-init rendering."
  type        = map(string)
  default     = {}
}
