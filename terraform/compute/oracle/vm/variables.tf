variable "name" {
  description = "Base name for the instance(s). Instances are keyed <name>-<replica> (name-1, name-2, …), matching compute/aws/ec2."
  type        = string
}

variable "replicas" {
  description = "Number of instances to create. The gateway calls with 1; whoami with N."
  type        = number
  default     = 1
}

variable "compartment_id" {
  description = "OCID of the compartment the instance(s) are created in (also the scope of the AD/image lookups)."
  type        = string
}

variable "availability_domain" {
  description = "Availability domain the instance(s) are placed in. Empty = the compartment's first AD."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "OCID of the existing subnet the instance VNIC(s) join."
  type        = string
}

variable "nsg_ids" {
  description = "Network security group OCIDs to attach to the VNIC(s)."
  type        = list(string)
  default     = []
}

variable "shape" {
  description = "Compute shape (flex shapes are sized by ocpus/memory_in_gbs)."
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "ocpus" {
  description = "OCPUs per instance (1 OCPU = 2 vCPUs on E4.Flex)."
  type        = number
  default     = 1
}

variable "memory_in_gbs" {
  description = "Memory (GB) per instance."
  type        = number
  default     = 4
}

variable "vm_image_ocid" {
  description = "Boot image OCID. Empty = latest Canonical Ubuntu 24.04 platform image for the shape."
  type        = string
  default     = ""
}

variable "enable_public_ip" {
  description = "Assign a public IP to each instance (requires a public subnet)."
  type        = bool
  default     = false
}

variable "user_data" {
  description = "Already-rendered cloud-init user data (opaque). Base64-encoded by the module before it lands in instance metadata."
  type        = string
  default     = ""
}

variable "freeform_tags" {
  description = "Freeform tags applied to every instance (the callers merge their common/role-specific tags before passing them in)."
  type        = map(string)
  default     = {}
}

variable "private_ips" {
  description = "Fixed private IPs, one per replica index (instance idx N gets private_ips[N]; extra instances fall back to DHCP). Each address must sit in subnet_id's CIDR outside OCI's reserved first-2/last-1 hosts. Pinning makes the address plan-known AND stable across instance recreation."
  type        = list(string)
  default     = []
}
