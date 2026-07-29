# =============================================================================
# compute/alibaba/eci — inputs
# =============================================================================
# Shared infra module for Alibaba ECI (Elastic Container Instance) container
# groups. Both traefik/alibaba-eci and apps/whoami/alibaba-eci compose it: the
# gateway maps a single group, whoami maps N (one container group per replica).
#
# The module owns the `alicloud_eci_container_group` resource and NOTHING
# role-specific. The container spec (image/commands/args/env/ports/mounts),
# volumes, RAM-role credential and discovery tags are the ROLE-SPECIFIC content
# — the caller renders them and passes them in as the OPAQUE `groups` map, the
# container-platform analog of a VM's rendered user_data.
# =============================================================================

variable "vswitch_id" {
  description = "ID of the existing vswitch every container group joins (the parent dials a group's private intranet IP in-VPC, e.g. compute/alibaba/vpc's vswitch_id)."
  type        = string
}

variable "security_group_id" {
  description = "Security group ID attached to every container group (required by ECI, e.g. compute/alibaba/vpc's security_group_id)."
  type        = string
}

variable "restart_policy" {
  description = "Container-group restart policy (Always | OnFailure | Never)."
  type        = string
  default     = "Always"
}

variable "groups" {
  description = <<-EOT
    Map of container groups to create, keyed by container_group_name (the key is
    used verbatim as the group name and as the output key). The gateway passes a
    single entry; whoami passes one per replica. Each group carries its already
    rendered, role-specific container spec, volumes, RAM role and tags — this
    module treats them as opaque and only owns the container-group resource.
  EOT
  type = map(object({
    cpu    = number
    memory = number
    # The metadata-served RAM role the container assumes (null = unset). Only the
    # Traefik child sets it (its alibabaECI provider's keyless credential).
    ram_role_name = optional(string)
    # Container specs (both callers declare exactly one). Fields left null/empty
    # are not emitted, so a caller that never sets commands/args/env/mounts
    # renders a container identical to a hand-written static block.
    containers = list(object({
      name     = string
      image    = string
      commands = optional(list(string))
      args     = optional(list(string))
      ports = optional(list(object({
        port     = number
        protocol = optional(string, "TCP")
      })), [])
      environment_vars = optional(map(string), {})
      volume_mounts = optional(list(object({
        name       = string
        mount_path = string
      })), [])
    }))
    # Container-group volumes (e.g. a ConfigFileVolume delivering file-provider
    # config). Empty for workloads that mount nothing.
    volumes = optional(list(object({
      name = string
      type = string
      config_file_volume_config_file_to_paths = optional(list(object({
        path    = string
        content = string
      })), [])
    })), [])
    # Dotted-key traefik.* tags — the alibabaECI provider's workload config.
    tags = optional(map(string), {})
  }))
}
