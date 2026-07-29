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

# The VMs, their NICs, optional public IPs, and optional NSG associations — the
# shared Azure VM fleet module this backend and traefik/azure-vm both compose
# (exactly like whoami/ec2 + traefik/ec2 share compute/aws/ec2). No identity:
# the whoami backends carry only their dotted discovery tags.
module "vm" {
  source = "../../../compute/azure/vm"

  apps = {
    for app_name, app_config in var.apps : app_name => {
      replicas = app_config.replicas
      tags     = try(app_config.tags, {})
    }
  }

  resource_group_name = var.resource_group_name
  location            = var.location
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  common_tags         = var.common_tags

  subnet_id                     = local.subnet_id
  network_security_group_id     = local.network_security_group_id
  enable_network_security_group = var.create_vnet || var.enable_network_security_group
  enable_public_ip              = var.enable_public_ip

  user_data = {
    for key, inst in local.instances_map : key => module.cloud_init[inst.app_name].rendered
  }
}
