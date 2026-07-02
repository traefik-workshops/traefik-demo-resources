variable "apps" {
  description = "Map of applications to deploy to VPC instances. Each app can have multiple replicas: { name = { replicas, port, name, environment, service_name } }. Optional `environment` (map) is merged over the module-level `environment` into the container. UNLIKE the ec2/alibaba-ecs siblings there are NO dotted traefik.* tags — `service_name` (default: the app key; keep it lowercase, IBM lowercases tags) becomes the instance user tag `<service_name_tag_key>:<service_name>`, assigning the instance to that service in the ibmVPC provider's base configuration file."
  type        = any
  default     = {}
}

variable "subnet_id" {
  description = "ID of the existing subnet the instances join (e.g. compute/ibm/vpc's subnet_id, so the Traefik child reaches these VMs in-VPC). The zone and VPC derive from it."
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs to attach to the instances (e.g. compute/ibm/vpc's security_group_ids — IBM security groups deny both directions by default, so attach one that allows the app port in and image pulls out)"
  type        = list(string)
}

variable "service_name_tag_key" {
  description = "User-tag key assigning an instance to a base-configuration service (tag format <key>:<service>). Must match the ibmVPC provider's serviceNameTagKey."
  type        = string
  default     = "traefik-service-name"
}

variable "instance_profile" {
  description = "VSI profile for all echo servers (default: 2 vCPU / 4 GB — the smallest VPC gen2 compute profile)"
  type        = string
  default     = "cx2-2x4"
}

variable "image_id" {
  description = "Boot image ID. Empty = latest stock Ubuntu 24.04 amd64 image."
  type        = string
  default     = ""
}

variable "ssh_key_ids" {
  description = "IBM Cloud SSH key IDs to inject (debugging convenience — whoami itself needs none)"
  type        = list(string)
  default     = []
}

variable "resource_group_id" {
  description = "Resource group ID the instances land in. Empty = the account's default resource group."
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common user tags (flat strings) to apply to all instances"
  type        = list(string)
  default     = []
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

variable "enable_floating_ip" {
  description = "Attach a floating IP to each instance (inbound access only). Off by default — the Traefik child dials private IPs (ipMode=private), and image pulls ride the subnet's public gateway."
  type        = bool
  default     = false
}
