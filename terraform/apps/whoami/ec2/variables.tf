variable "apps" {
  description = "Map of applications to deploy to EC2. Each app can have multiple replicas."
  type        = any
  default     = {}
}

variable "instance_type" {
  description = "EC2 instance type for all echo servers"
  type        = string
  default     = "t3.micro"
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

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
  default     = []
}

variable "whoami_version" {
  description = "The Whoami version to install. Must be a real traefik/whoami image tag — they carry a `v` prefix (e.g. v1.11.0); a bare `1.11.0` is `manifest unknown` and the binary extraction silently fails."
  type        = string
  default     = "v1.11.0"
}

variable "ami_architecture" {
  description = "The architecture (x86_64, arm64)"
  type        = string
  default     = "x86_64"
}
