variable "apps" {
  description = "Map of applications to deploy with multiple replicas"
  type = map(object({
    replicas            = optional(number, 1)
    subnet_ids          = optional(list(string), [])
    port                = optional(number, 80)
    docker_image        = optional(string, "traefik/whoami:latest")
    docker_options      = optional(string, "") # Docker run flags: -e, -p, -v, etc.
    container_arguments = optional(string, "") # Container CMD/ARGS: --flag=value, etc.
    tags                = optional(map(string), {})
  }))
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "ami_architecture" {
  description = "AMI architecture (x86_64 or arm64)"
  type        = string
  default     = "x86_64"
}

variable "replica_start_index" {
  description = "Starting index for replica numbering (Default: 1)"
  type        = number
  default     = 1
}

variable "common_tags" {
  description = "Common tags to apply to all instances"
  type        = map(string)
  default     = {}
}

variable "create_vpc" {
  description = "Create VPC if vpc_id is not provided"
  type        = bool
  default     = true
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.subnet_ids) != 0
    error_message = "subnet_ids must be provided if create_vpc is false"
  }
}

variable "security_group_ids" {
  description = "List of security group IDs to associate with the instances (used if not creating VPC)"
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.security_group_ids) != 0
    error_message = "security_group_ids must be provided if create_vpc is false"
  }
}

variable "iam_instance_profile" {
  description = "IAM instance profile name to attach to EC2 instances"
  type        = string
  default     = ""
}

variable "enable_acme_setup" {
  description = "Enable ACME storage setup for Let's Encrypt certificates"
  type        = bool
  default     = false
}

variable "user_data_override" {
  description = "Optional user data script to override the default Docker-based generation"
  type        = string
  default     = ""
}

variable "user_data_overrides" {
  description = "Optional map of user data scripts to override the default Docker-based generation per instance key"
  type        = map(string)
  default     = {}
}

variable "root_block_device_size" {
  description = "Root block device size in GB. Must be >= the AMI's root snapshot — the Amazon Linux 2023 AMI snapshot is 30GB, so 20 now fails RunInstances with InvalidBlockDeviceMapping."
  type        = number
  default     = 30
}

variable "associate_public_ip_address" {
  description = "Associate a public IP address with an instance in a VPC"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = ""

  validation {
    condition     = var.create_vpc || var.vpc_id != ""
    error_message = "vpc_id must be provided if create_vpc is false"
  }
}

variable "extra_ingress_ports" {
  description = "Additional TCP ports to open on the created VPC's security group (only when create_vpc = true). Passed through to compute/aws/vpc — e.g. [9443] for a Hub multicluster uplink entrypoint."
  type        = list(number)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway in the VPC (only when create_vpc = true). Defaults false — these instances run in PUBLIC subnets with public IPs (IGW egress), so the NAT (which only serves the unused private subnets) is pure cost."
  type        = bool
  default     = false
}

variable "private_ips" {
  type        = list(string)
  description = "Fixed private IPs, one per instance index (instance idx N gets private_ips[N]; extra instances fall back to DHCP). Each address must sit in the subnet that instance lands in (subnet_ids[idx % length]) and avoid AWS's reserved first-4/last-1 hosts. Pinning makes the address plan-known AND stable across instance recreation — a hub dialing this child never goes stale."
  default     = []
}
