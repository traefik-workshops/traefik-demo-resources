# whoami on Azure Container Instances — the ACI sibling of apps/whoami/ecs.
# Each app replica is one container group with a private, vnet-injected IP;
# its Azure TAGS (dotted keys, exactly like ECS docker labels) are what a
# Traefik Hub aci provider discovers. The provided subnet MUST be delegated to
# Microsoft.ContainerInstance (compute/azure/vnet's aci_subnet_id already is).

locals {
  # A tag is a `:` in the LAST path segment (a registry host may carry a :port).
  image_last_segment = element(split("/", var.whoami_image), length(split("/", var.whoami_image)) - 1)
  image              = length(regexall(":", local.image_last_segment)) > 0 ? var.whoami_image : "${var.whoami_image}:${var.whoami_version}"

  # Same instance-key scheme as the ec2/azure-vm siblings: "<app>-<replica>".
  groups = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key         = "${app_name}-${replica_idx + 1}"
        app_name    = app_name
        port        = try(app_config.port, 80)
        name        = try(app_config.name, app_name)
        environment = try(app_config.environment, {})
        tags        = try(app_config.tags, {})
      }
    ]
  ])

  groups_map = { for grp in local.groups : grp.key => grp }

  subnet_id = var.create_vnet ? module.vnet[0].aci_subnet_id : var.subnet_id
}

# Escape hatch mirroring the azure-vm sibling — off by default; these
# container groups normally join the demo's existing (delegated) subnet.
module "vnet" {
  count  = var.create_vnet ? 1 : 0
  source = "../../../compute/azure/vnet"

  name                = "whoami-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_container_group" "whoami" {
  for_each = local.groups_map

  name                = each.key
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  restart_policy      = "Always"

  # Private vnet-injected IP — the Traefik child dials it in-vnet (ipMode=private).
  ip_address_type = "Private"
  subnet_ids      = [local.subnet_id]

  container {
    name   = "whoami"
    image  = local.image
    cpu    = var.container_cpu
    memory = var.container_memory

    # The declared exposed port doubles as the aci provider's fallback when no
    # traefik.*.loadbalancer.server.port tag is set (lowest declared port).
    ports {
      port     = each.value.port
      protocol = "TCP"
    }

    # Built-ins first so module/per-app env can override them.
    environment_variables = merge(
      {
        # WHOAMI_NAME -> body shows `Name: <name>` (e.g. whoami-aci).
        WHOAMI_NAME        = each.value.name
        WHOAMI_PORT_NUMBER = tostring(each.value.port)
      },
      var.environment,
      each.value.environment,
    )
  }

  # Dotted-key traefik.* tags — the aci provider's workload config,
  # exactly like ECS docker labels.
  tags = merge(var.common_tags, each.value.tags)
}
