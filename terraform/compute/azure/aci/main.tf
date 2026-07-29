# =============================================================================
# compute/azure/aci — the shared azurerm_container_group both the Traefik child
# (traefik/aci) and the whoami backend (apps/whoami/aci) compose.
# =============================================================================
# One container group per entry in var.container_groups (the traefik caller
# passes a single entry; whoami passes one per app replica). Every attribute is
# moved verbatim from the two callers' former inline resources — role-specific
# content (commands, tags, env, secret volumes, identity) arrives as inputs.
# =============================================================================

resource "azurerm_container_group" "this" {
  for_each = var.container_groups

  name                = each.key
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = var.os_type
  restart_policy      = var.restart_policy

  # Private vnet-injected IP — the parent/child dials it in-vnet (ipMode=private).
  # The subnet MUST be delegated to Microsoft.ContainerInstance.
  ip_address_type = var.ip_address_type
  subnet_ids      = [var.subnet_id]

  # DefaultAzureCredential inside the container resolves this identity via the
  # ACI-injected identity endpoint (the Traefik child's aci-provider credential).
  dynamic "identity" {
    for_each = var.enable_system_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  dynamic "exposed_port" {
    for_each = toset(var.exposed_ports)
    content {
      port     = exposed_port.value
      protocol = "TCP"
    }
  }

  container {
    name     = var.container_name
    image    = var.image
    cpu      = var.container_cpu
    memory   = var.container_memory
    commands = var.commands

    dynamic "ports" {
      for_each = toset(each.value.ports)
      content {
        port     = ports.value
        protocol = "TCP"
      }
    }

    environment_variables = each.value.environment_variables

    # The Hub image is scratch (no shell/cloud-init) — a secret volume carries
    # the file-provider config, no init sidecar needed (unlike ECS).
    dynamic "volume" {
      for_each = var.volumes
      content {
        name       = volume.value.name
        mount_path = volume.value.mount_path
        secret     = volume.value.secret
      }
    }
  }

  tags = merge(var.common_tags, each.value.tags)
}
