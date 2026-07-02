variable "apps" {
  description = "Map of applications to deploy to OCI Container Instances. Each app can have multiple replicas (one container instance each). Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` become dotted-key traefik.* freeform tags."
  type        = any
  default     = {}
}

variable "compartment_id" {
  description = "OCID of the compartment the container instances are created in"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain the container instances are placed in. Empty = the compartment's first AD (same pick as compute/oracle/oke)."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "OCID of the existing subnet the container instance VNICs join (e.g. compute/oracle/oke's nodes_subnet_id, so the Traefik child reaches them in-VCN)"
  type        = string
}

variable "nsg_ids" {
  description = "Network security group OCIDs to attach to the container instance VNICs. Also what the ocici provider's opt-in nsgPortDiscovery reads ports from."
  type        = list(string)
  default     = []
}

variable "shape" {
  description = "Container instance shape (flex shapes are sized by container_ocpus/container_memory_in_gbs)"
  type        = string
  default     = "CI.Standard.E4.Flex"
}

variable "container_ocpus" {
  description = "OCPUs per container instance (1 OCPU = 2 vCPUs on E4.Flex)"
  type        = number
  default     = 1
}

variable "container_memory_in_gbs" {
  description = "Memory (GB) per container instance"
  type        = number
  default     = 2
}

variable "common_tags" {
  description = "Common freeform tags to apply to all container instances"
  type        = map(string)
  default     = {}
}

variable "whoami_image" {
  description = "Whoami image every container instance runs. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "docker.io/zalbiraw/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables added to every whoami container, e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}
