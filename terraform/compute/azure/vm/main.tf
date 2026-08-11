# =============================================================================
# compute/azure/vm — the shared Azure Linux VM fleet
# =============================================================================
# Owns ONLY infra: the VM, its NIC, the optional public IP, and the optional
# NSG association. Both traefik/azure-vm (one VM, SystemAssigned identity) and
# apps/whoami/azure-vm (N whoami backends, no identity) compose this — exactly
# like traefik/ec2 and whoami/ec2 share compute/aws/ec2. Nothing role-specific
# lives here: custom_data arrives already rendered (opaque user_data), tags
# arrive pre-merged, and the Traefik Reader-role identity_bounce stays in the
# traefik caller.
# =============================================================================

locals {
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        instance_key = "${app_name}-${replica_idx + var.replica_start_index}"
        app_tags     = app_config.tags
      }
    ]
  ])

  # Map for for_each with a global index so private_ips[idx] pins evenly.
  instances_map = {
    for idx, inst in local.instances : inst.instance_key => merge(inst, {
      idx = idx
    })
  }
}

resource "azurerm_public_ip" "vm" {
  for_each = var.enable_public_ip ? local.instances_map : {}

  name                = "${each.key}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  for_each = local.instances_map

  name                = "${each.key}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = try(var.private_ips[each.value.idx], null) != null ? "Static" : "Dynamic"
    private_ip_address            = try(var.private_ips[each.value.idx], null)
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.vm[each.key].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  # Gated on the config-known bool, not the id: same-run ids are unknown at plan
  # and for_each cannot depend on them (first fresh apply failed here, 2026-07).
  for_each = var.enable_network_security_group ? local.instances_map : {}

  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = var.network_security_group_id
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each = local.instances_map

  # Ordered against the NSG association ON PURPOSE, and the reason is TEARDOWN.
  #
  # Deleting an association is not a delete at the Azure API — it is a NIC
  # CreateOrUpdate that clears the NSG. Both this VM and the association hang off the
  # same NIC and nothing else related them, so terraform destroyed them concurrently
  # and the NIC update landed against a VM the platform had already accepted a delete
  # for. azure-unified-ingress, 2026-08-11:
  #
  #   Error: updating Network Interface (... "whoami-1-nic"): polling after
  #   CreateOrUpdate: Status: "OperationNotAllowed"
  #   Message: "Operation 'startTenantUpdate' is not allowed on VM 'whoami-1' since
  #   the VM is marked for deletion."
  #
  # That failure aborts the destroy with the AKS cluster, both VNets, the NSGs and the
  # NICs still standing and BILLING, and the teardown auditor rightly fails the run.
  #
  # Making the VM depend on the association destroys the VM FIRST, to completion, and
  # only then clears the NSG off an unattached NIC. The create direction improves too:
  # the NIC is bound to the NSG before the VM boots behind it, rather than shortly
  # after.
  depends_on = [azurerm_network_interface_security_group_association.vm]

  name                = each.key
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size

  network_interface_ids = [azurerm_network_interface.vm[each.key].id]

  admin_username = var.admin_username
  admin_password = var.admin_password
  # Demo-grade: these VMs are driven over password auth (admin_password var +
  # cloud-init user-data) — no per-demo SSH key wiring exists. Suppressed inline
  # rather than repo-wide (.tfsec.yml) to keep the blast radius to this resource.
  #tfsec:ignore:azure-compute-disable-password-authentication
  disable_password_authentication = false

  custom_data = base64encode(var.user_data[each.key])

  # Optional managed identity (Traefik: SystemAssigned for the azureVM provider's
  # DefaultAzureCredential, resolved via IMDS thanks to --network host in the
  # cloud-init's docker run). Absent for the whoami backends (identity_type null).
  dynamic "identity" {
    for_each = var.identity_type != null ? [1] : []
    content {
      type = var.identity_type
    }
  }

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

  # Dotted-key traefik.* tags — the azureVM provider's workload config, exactly
  # like EC2 instance tags. Pre-merged by the caller; app tags win over common.
  tags = merge(var.common_tags, each.value.app_tags)
}
