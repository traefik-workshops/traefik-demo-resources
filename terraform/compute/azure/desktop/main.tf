# =============================================================================
# Azure recording workstation — a generic Demo Studio capture desktop
# =============================================================================
# Ubuntu 24.04 + GNOME + xrdp on a dummy Xorg pinned to 1920x1080, the full dev
# toolchain, and the recording stack (ffmpeg, wmctrl, xdotool). One VM serves any
# demo's record-section. Forked from traefik/azure-vm (VM/NIC/pip/identity/role
# skeleton) with the entire Hub surface dropped — this VM runs no gateway.
# =============================================================================

data "azurerm_client_config" "current" {}

locals {
  user_data = templatefile("${path.module}/cloud-init/desktop.tpl", {
    admin_username             = var.admin_username
    admin_password             = var.admin_password
    rdp_resolution             = var.rdp_resolution
    rdp_color_depth            = var.rdp_color_depth
    enable_recording_toolchain = var.enable_recording_toolchain
    dev_toolchain              = var.dev_toolchain
    git_deploy_key             = var.git_deploy_key
    git_repo_url               = var.git_repo_url
    extra_files                = var.extra_files
  })
}

resource "azurerm_public_ip" "desktop" {
  count = var.enable_public_ip ? 1 : 0

  name                = "${var.vm_name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "desktop" {
  count = var.enable_nsg ? 1 : 0

  name                = "${var.vm_name}-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.source_address_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowRDP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.source_address_prefix
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "desktop" {
  name                = "${var.vm_name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.desktop[0].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "desktop" {
  count = var.enable_nsg ? 1 : 0

  network_interface_id      = azurerm_network_interface.desktop.id
  network_security_group_id = azurerm_network_security_group.desktop[0].id
}

resource "azurerm_linux_virtual_machine" "desktop" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size

  network_interface_ids = [azurerm_network_interface.desktop.id]

  admin_username = var.admin_username
  admin_password = var.admin_password
  # Demo-grade: the workstation is driven over password auth (SSH + RDP) for the
  # operator. Scoped suppression, matching traefik/azure-vm.
  #tfsec:ignore:azure-compute-disable-password-authentication
  disable_password_authentication = false

  custom_data = base64encode(local.user_data)

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  # Phase A: vanilla Ubuntu 24.04 + cloud-init. Phase B: a golden image via source_image_id.
  source_image_id = var.source_image_id != "" ? var.source_image_id : null

  dynamic "source_image_reference" {
    for_each = var.source_image_id == "" ? [1] : []
    content {
      publisher = "Canonical"
      offer     = "ubuntu-24_04-lts"
      sku       = "server"
      version   = "latest"
    }
  }

  tags = var.extra_tags
}

resource "azurerm_role_assignment" "identity" {
  count = var.enable_reader_role || var.enable_contributor_role ? 1 : 0

  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = var.enable_contributor_role ? "Contributor" : "Reader"
  principal_id         = azurerm_linux_virtual_machine.desktop.identity[0].principal_id
}
