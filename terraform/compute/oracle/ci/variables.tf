# =============================================================================
# compute/oracle/ci — OCI Container Instance primitive
# =============================================================================
# Owns the oci_container_instances_container_instance resource (one per entry in
# var.instances) plus the VNIC IP resolution, and NOTHING role-specific: the
# per-instance container definition (image, command, env, health checks, mounts)
# and CONFIGFILE volumes are handed in as OPAQUE structured payloads. The Traefik
# gateway composes a single instance; whoami composes N. Both pass the container
# and volume blocks already rendered by their own role logic.
# =============================================================================

variable "compartment_id" {
  description = "OCID of the compartment the container instances are created in."
  type        = string
}

variable "availability_domain" {
  description = "Availability domain the container instances are placed in. Empty = the compartment's first AD."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "OCID of the existing subnet each container-instance VNIC joins."
  type        = string
}

variable "nsg_ids" {
  description = "Network security group OCIDs to attach to each container-instance VNIC."
  type        = list(string)
  default     = []
}

variable "enable_public_ip" {
  description = "Assign a public IP to each container-instance VNIC (is_public_ip_assigned)."
  type        = bool
  default     = false
}

variable "shape" {
  description = "Container instance shape (flex shapes are sized by container_ocpus/container_memory_in_gbs)."
  type        = string
  default     = "CI.Standard.E4.Flex"
}

variable "container_ocpus" {
  description = "OCPUs for each container instance (1 OCPU = 2 vCPUs on E4.Flex)."
  type        = number
  default     = 1
}

variable "container_memory_in_gbs" {
  description = "Memory (GB) for each container instance."
  type        = number
  default     = 4
}

variable "instances" {
  description = <<-EOT
    Map of container instances to create, keyed by instance name (the key becomes
    the for_each key and the outputs' key). Each entry carries the already-rendered,
    OPAQUE container + volume payload — this module renders it verbatim and does not
    interpret its contents (no whoami/traefik-hub logic here).

    - display_name  : the instance's display name.
    - freeform_tags : freeform tags for the instance (the discovered workload config
                      / discovery tags — the module passes them through untouched).
    - private_ip    : optional static private IP for the VNIC (null = provider-assigned).
    - containers    : list of container blocks (image_url, optional command/arguments/
                      environment_variables, optional TCP health check, volume mounts).
    - volumes       : list of CONFIGFILE volume blocks (already base64-encoded configs).
  EOT
  type = map(object({
    display_name  = string
    freeform_tags = optional(map(string), {})
    private_ip    = optional(string, null)
    containers = list(object({
      display_name          = string
      image_url             = string
      command               = optional(list(string), null)
      arguments             = optional(list(string), null)
      environment_variables = optional(map(string), null)
      health_checks = optional(object({
        health_check_type = string
        port              = number
      }), null)
      volume_mounts = optional(list(object({
        volume_name = string
        mount_path  = string
      })), [])
    }))
    volumes = optional(list(object({
      name        = string
      volume_type = string
      configs = list(object({
        file_name = string
        data      = string
      }))
    })), [])
  }))
}
