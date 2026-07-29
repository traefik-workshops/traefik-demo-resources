variable "apps" {
  description = "Map of applications to deploy to OCI VMs. Each app can have multiple replicas. Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` become dotted-key traefik.* freeform tags."
  type        = any
  default     = {}
}

variable "compartment_id" {
  description = "OCID of the compartment the VMs are created in"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain the VMs are placed in. Empty = the compartment's first AD (same pick as compute/oracle/oke)."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "OCID of the existing subnet the VM VNICs join (e.g. compute/oracle/oke's nodes_subnet_id, so the Traefik child reaches these VMs in-VCN)"
  type        = string
}

variable "nsg_ids" {
  description = "Network security group OCIDs to attach to the VM VNICs. Also what the oci provider's opt-in nsgPortDiscovery reads ports from."
  type        = list(string)
  default     = []
}

variable "shape" {
  description = "Compute shape for all echo servers (flex shapes are sized by ocpus/memory_in_gbs)"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "ocpus" {
  description = "OCPUs per VM (1 OCPU = 2 vCPUs on E4.Flex)"
  type        = number
  default     = 1
}

variable "memory_in_gbs" {
  description = "Memory (GB) per VM"
  type        = number
  default     = 2
}

variable "vm_image_ocid" {
  description = "Boot image OCID. Empty = latest Canonical Ubuntu 24.04 platform image for the shape."
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common freeform tags to apply to all VMs"
  type        = map(string)
  default     = {}
}

variable "whoami_image" {
  description = "Whoami image to docker-run on each VM. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "ghcr.io/zalbiraw/whoami:latest"
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
  description = "Assign a public IP to each VM (requires a public subnet). Off by default — the Traefik child dials private IPs (ipMode=private)."
  type        = bool
  default     = false
}
