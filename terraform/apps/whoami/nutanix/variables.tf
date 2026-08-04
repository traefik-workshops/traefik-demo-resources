variable "vm_name" {
  description = "Name of the VM"
  type        = string
}

# SPLIT FROM vm_name deliberately. Prism Central VM names must be UNIQUE, and a caller that
# fans one whoami out per VM (the nutanixprismcentral provider reads exactly ONE
# TraefikServiceName category value per VM, so a fleet is N uniquely-named VMs) therefore
# has N distinct vm_names. Before this variable existed main.tf passed vm_name straight
# through as the whoami `-name`, so the bodies echoed `Name: whoami-vm-1` / `whoami-vm-2` —
# and the shared assertion suite, which sorts -u the `Name:` values inside ONE sticky cookie
# jar, reads a correctly-pinned session as "sticky crossed legs — 2 distinct legs". The VM
# names must differ; the whoami Name must not.
variable "name" {
  description = "The whoami `-name` (WHOAMI_NAME) the response body echoes as `Name: <name>`. Empty falls back to vm_name (the historical behaviour). Set it — identical across the fleet — whenever more than one VM fronts the same logical leg."
  type        = string
  default     = ""
}

variable "cluster_id" {
  description = "UUID of the Nutanix Cluster"
  type        = string
}

variable "subnet_uuid" {
  description = "UUID of the Subnet"
  type        = string
}

variable "image_id" {
  description = "UUID of the Image to use"
  type        = string
}

variable "arch" {
  description = "Architecture of the VM"
  type        = string
  default     = "amd64"
}

variable "vm_num_vcpus_per_socket" {
  description = "Number of vCPUs per socket"
  type        = number
  default     = 1
}

variable "vm_num_sockets" {
  description = "Number of sockets"
  type        = number
  default     = 1
}

variable "vm_memory_mib" {
  description = "Memory size in MiB"
  type        = number
  default     = 1024
}

variable "service_name" {
  description = "Service name for Nutanix Prism Central discovery (TraefikServiceName category)"
  type        = string
  default     = "whoami"
}

variable "service_port" {
  description = "Service port for Nutanix Prism Central discovery (TraefikServicePort category)"
  type        = number
  default     = 8080
}

variable "load_balancer_strategy" {
  description = "Load balancer strategy for Nutanix Prism Central discovery (TraefikLoadBalancerStrategy category)"
  type        = string
  default     = ""
}

variable "whoami_image" {
  description = "Whoami image to docker-run on the VM. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "ghcr.io/zalbiraw/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables passed to the whoami container (docker -e), e.g. OTEL_* exporter config for the OTel-instrumented whoami fork."
  type        = map(string)
  default     = {}
}

# Empty = DHCP (overlay subnets / VPCs always have it; VLAN subnets often have a
# small pool that can be exhausted). Set this when the target subnet's DHCP pool
# is full or you want predictable IPs to reference from Traefik routes.
variable "static_ip" {
  description = "Static IP for the whoami VM NIC. Empty means DHCP."
  type        = string
  default     = ""
}
