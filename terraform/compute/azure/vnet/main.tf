# Demo VNet mirroring compute/aws/vpc: one VNet, a subnet for VMs, a subnet
# delegated to Microsoft.ContainerInstance (ACI vnet injection requires a
# dedicated delegated subnet), and an NSG opening the same demo ports as the
# AWS security group (80/443/8080/22 + extra_ingress_ports).

resource "azurerm_virtual_network" "demo" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.cidr]
}

resource "azurerm_subnet" "vms" {
  name                 = "${var.name}-vms"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.demo.name
  address_prefixes     = [var.vm_subnet_cidr]
}

# ACI container groups with private (vnet-injected) IPs can only land in a
# subnet delegated to Microsoft.ContainerInstance — and nothing else can share
# that subnet, hence the split from the VM subnet.
resource "azurerm_subnet" "aci" {
  name                 = "${var.name}-aci"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.demo.name
  address_prefixes     = [var.aci_subnet_cidr]

  delegation {
    name = "aci"

    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

locals {
  ingress_rules = merge(
    {
      http  = { port = 80, priority = 100 }
      https = { port = 443, priority = 110 }
      alt   = { port = 8080, priority = 120 }
      ssh   = { port = 22, priority = 130 }
    },
    {
      # Extra ports (e.g. the Hub multicluster uplink :9443 on VM/ACI spokes)
      for idx, port in var.extra_ingress_ports :
      "extra-${port}" => { port = port, priority = 200 + idx * 10 }
    }
  )
}

resource "azurerm_network_security_group" "demo" {
  name                = "${var.name}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_network_security_rule" "ingress" {
  for_each = local.ingress_rules

  name                        = "allow-${each.key}"
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(each.value.port)
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.demo.name
}

resource "azurerm_subnet_network_security_group_association" "vms" {
  subnet_id                 = azurerm_subnet.vms.id
  network_security_group_id = azurerm_network_security_group.demo.id
}

resource "azurerm_subnet_network_security_group_association" "aci" {
  subnet_id                 = azurerm_subnet.aci.id
  network_security_group_id = azurerm_network_security_group.demo.id
}
