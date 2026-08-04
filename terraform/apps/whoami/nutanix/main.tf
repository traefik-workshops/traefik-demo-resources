locals {
  # Build category map for service discovery using hardcoded default keys
  service_categories = var.service_name != "" ? merge(
    {
      "TraefikServiceName" = var.service_name
      "TraefikServicePort" = tostring(var.service_port)
    },
    var.load_balancer_strategy != "" ? {
      "TraefikLoadBalancerStrategy" = var.load_balancer_strategy
    } : {}
  ) : {}
}

# Use shared cloud-init module
module "cloud_init" {
  source = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  arch           = var.arch
  port           = var.service_port
  # Surfaces as `Name:` in the whoami response. Defaults to vm_name so a single VM still
  # names itself, but a fleet fronting ONE logical leg must override it (var.name) so every
  # member answers with the SAME Name — see the variable's comment for what breaks.
  #
  # `Hostname:` still differs per VM even when Name is shared: cloud-init never sets the OS
  # hostname (it stays "ubuntu"), so whoami reports its own CONTAINER id, which is random
  # per `docker run`. That is what a wrr spread assertion actually counts.
  name        = var.name != "" ? var.name : var.vm_name
  environment = var.environment
}

module "whoami_vm" {
  source = "../../../compute/nutanix/vm"

  name                 = var.vm_name
  cluster_uuid         = var.cluster_id
  subnet_uuid          = var.subnet_uuid
  image_uuid           = var.image_id
  num_vcpus_per_socket = var.vm_num_vcpus_per_socket
  num_sockets          = var.vm_num_sockets
  memory_size_mib      = var.vm_memory_mib

  # Apply service discovery categories
  categories = local.service_categories

  # Empty default → DHCP. Set when the subnet's pool can't fit all whoami VMs.
  static_ip = var.static_ip

  cloud_init_user_data = module.cloud_init.rendered
}
