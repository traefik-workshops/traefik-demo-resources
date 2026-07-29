variable "name" {
  description = "Base name for the instances. Each replica is named \"<name>-<index>\"."
  type        = string
}

variable "replicas" {
  description = "Number of instances to create (the gateway calls with 1, whoami with N)."
  type        = number
  default     = 1
}

variable "replica_start_index" {
  description = "Starting index for replica numbering (Default: 1)."
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "ECS instance type."
  type        = string
  default     = "ecs.e-c1m2.large"
}

variable "image_id" {
  description = "Boot image ID. Empty = latest public Ubuntu 24.04 x64 image."
  type        = string
  default     = ""
}

variable "system_disk_category" {
  description = "System disk category. ESSD Entry pairs with the economy (e-series) instance types; switch to cloud_essd for g/c families."
  type        = string
  default     = "cloud_essd_entry"
}

variable "system_disk_size" {
  description = "System disk size (GB) per instance."
  type        = number
  default     = 40
}

variable "vswitch_id" {
  description = "ID of the existing vswitch the instances join (e.g. compute/alibaba/vpc's vswitch_id)."
  type        = string
}

variable "security_group_ids" {
  description = "Existing security group IDs to attach to the instances (Alibaba requires at least one unless enable_security_group is on, e.g. compute/alibaba/vpc's security_group_ids)."
  type        = list(string)
  default     = []
}

variable "enable_public_ip" {
  description = "Allocate a public IP to each instance (Alibaba grants one when outbound bandwidth > 0). Off by default — callers dial private IPs; without it, docker pulls need a NAT gateway on the vswitch."
  type        = bool
  default     = false
}

variable "user_data" {
  description = "Fully-rendered cloud-init/user-data as an opaque string. The module base64-encodes it before handing it to the instance."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to every instance in this call (dotted-key traefik.* tags are the alibabaECS provider's workload/dashboard config)."
  type        = map(string)
  default     = {}
}

variable "private_ips" {
  description = "Fixed private IPs, one per instance index (instance idx N gets private_ips[N]; extra instances fall back to DHCP). Each address must sit in vswitch_id's CIDR outside Alibaba's reserved first-3/last-1 hosts. Pinning makes the address plan-known AND stable across instance recreation."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Optional module-created security group (mirrors the gateway's enable_security_group)
# -----------------------------------------------------------------------------

variable "enable_security_group" {
  description = "Create a security group opening security_group_ingress_ports to the instances from security_group_source_cidr (mirrors traefik/oci-vm's enable_nsg). Off by default — compute/alibaba/vpc's group already opens the demo ports. Requires vpc_id."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "ID of the VPC the module-created security group is created in. Only required when enable_security_group = true."
  type        = string
  default     = ""
}

variable "security_group_ingress_ports" {
  description = "TCP ports the module-created security group opens on the instances. Default covers HTTP(S), the dashboard, and the Hub multicluster uplink entrypoint (:9443) the parent dials."
  type        = list(number)
  default     = [80, 443, 8080, 9443]
}

variable "security_group_source_cidr" {
  description = "Source CIDR the module-created security group allows. Default covers RFC1918 VPCs (compute/alibaba/vpc's VPC is 10.0.0.0/16)."
  type        = string
  default     = "10.0.0.0/8"
}
