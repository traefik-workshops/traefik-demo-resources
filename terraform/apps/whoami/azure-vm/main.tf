# whoami on Azure Linux VMs — the azure-vm sibling of apps/whoami/ec2.
# Reuses the whoami/cloud-init template (docker-run systemd unit);
# each app replica is one small VM whose Azure TAGS (dotted keys, exactly like
# EC2 instance tags) are what a Traefik Hub azureVM provider discovers.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-azure-vm).
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

locals {
  # Replicate the ec2 sibling's instance-key scheme: "<app>-<replica>".
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key      = "${app_name}-${replica_idx + 1}"
        app_name = app_name
        tags     = try(app_config.tags, {})
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }

  subnet_id                 = var.create_vnet ? module.vnet[0].vm_subnet_id : var.subnet_id
  network_security_group_id = var.create_vnet ? module.vnet[0].network_security_group_id : var.network_security_group_id
}

# Escape hatch mirroring the ec2 sibling's create_vpc — but defaulted OFF:
# these VMs normally join the demo's existing VNet so the Traefik child can
# reach them privately.
module "vnet" {
  count  = var.create_vnet ? 1 : 0
  source = "../../../compute/azure/vnet"

  name                = "whoami-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_public_ip" "whoami" {
  for_each = var.enable_public_ip ? local.instances_map : {}

  name                = "${each.key}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "whoami" {
  for_each = local.instances_map

  name                = "${each.key}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.whoami[each.key].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "whoami" {
  for_each = local.network_security_group_id != "" ? local.instances_map : {}

  network_interface_id      = azurerm_network_interface.whoami[each.key].id
  network_security_group_id = local.network_security_group_id
}

resource "azurerm_linux_virtual_machine" "whoami" {
  for_each = local.instances_map

  name                = each.key
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size

  network_interface_ids = [azurerm_network_interface.whoami[each.key].id]

  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false

  custom_data = base64encode(module.cloud_init[each.value.app_name].rendered)

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Dotted-key traefik.* tags — the azureVM provider's workload config,
  # exactly like EC2 instance tags.
  tags = merge(var.common_tags, each.value.tags)
}
