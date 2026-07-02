variable "apps" {
  description = "Map of applications to deploy to ECS instances. Each app can have multiple replicas. Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` become dotted-key traefik.* instance tags."
  type        = any
  default     = {}
}

variable "vswitch_id" {
  description = "ID of the existing vswitch the instances join (e.g. compute/alibaba/vpc's vswitch_id, so the Traefik child reaches these VMs in-VPC)"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs to attach to the instances (Alibaba requires at least one, e.g. compute/alibaba/vpc's security_group_ids). Also what the alibabaECS provider's opt-in securityGroupPortDiscovery reads ports from."
  type        = list(string)
}

variable "instance_type" {
  description = "ECS instance type for all echo servers (default: 2 vCPU / 2 GB economy — the smallest that runs docker reliably)"
  type        = string
  default     = "ecs.e-c1m1.large"
}

variable "system_disk_category" {
  description = "System disk category. ESSD Entry pairs with the economy (e-series) default instance type; switch to cloud_essd for g/c families."
  type        = string
  default     = "cloud_essd_entry"
}

variable "system_disk_size" {
  description = "System disk size (GB) per instance"
  type        = number
  default     = 40
}

variable "image_id" {
  description = "Boot image ID. Empty = latest public Ubuntu 24.04 x64 image."
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all instances"
  type        = map(string)
  default     = {}
}

variable "whoami_image" {
  description = "Whoami image to docker-run on each instance. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "docker.io/zalbiraw/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables passed to every whoami container (docker -e), e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}

variable "enable_public_ip" {
  description = "Allocate a public IP to each instance (Alibaba grants one when outbound bandwidth > 0). Off by default — the Traefik child dials private IPs (ipMode=private); without it, docker pulls need a NAT gateway on the vswitch."
  type        = bool
  default     = false
}
