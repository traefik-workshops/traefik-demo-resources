# =============================================================================
# compute/alibaba/eci — the shared Alibaba ECI container group
# =============================================================================
# One `alicloud_eci_container_group` per entry in var.groups. This is the infra
# resource that both traefik/alibaba-eci and apps/whoami/alibaba-eci used to
# declare inline; it is moved here verbatim and generalized over var.groups so
# both roles compose the same module. All role-specific content (container
# spec, volumes, RAM role, tags) arrives pre-rendered in var.groups.
# =============================================================================

resource "alicloud_eci_container_group" "this" {
  for_each = var.groups

  container_group_name = each.key
  restart_policy       = var.restart_policy

  # Private vswitch IP — the parent dials the group in-VPC.
  vswitch_id        = var.vswitch_id
  security_group_id = var.security_group_id

  cpu    = each.value.cpu
  memory = each.value.memory

  # The metadata-served credential the caller's provider default chain ends on
  # (null when the group needs no RAM role).
  ram_role_name = each.value.ram_role_name

  dynamic "containers" {
    for_each = each.value.containers
    content {
      name     = containers.value.name
      image    = containers.value.image
      commands = containers.value.commands
      args     = containers.value.args

      dynamic "ports" {
        for_each = containers.value.ports
        content {
          port     = ports.value.port
          protocol = ports.value.protocol
        }
      }

      dynamic "environment_vars" {
        for_each = containers.value.environment_vars
        content {
          key   = environment_vars.key
          value = environment_vars.value
        }
      }

      dynamic "volume_mounts" {
        for_each = containers.value.volume_mounts
        content {
          name       = volume_mounts.value.name
          mount_path = volume_mounts.value.mount_path
        }
      }
    }
  }

  dynamic "volumes" {
    for_each = each.value.volumes
    content {
      name = volumes.value.name
      type = volumes.value.type

      dynamic "config_file_volume_config_file_to_paths" {
        for_each = volumes.value.config_file_volume_config_file_to_paths
        content {
          path    = config_file_volume_config_file_to_paths.value.path
          content = config_file_volume_config_file_to_paths.value.content
        }
      }
    }
  }

  tags = each.value.tags
}
