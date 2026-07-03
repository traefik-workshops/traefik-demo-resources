# =============================================================================
# Azure VM Traefik Deployment — the multicluster CHILD on Azure
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2. One VM runs the Hub
# image as a docker container (the cloud-init preview-image path) with a
# system-assigned managed identity: the azureVM provider authenticates via
# DefaultAzureCredential (IMDS works with --network host) and a Reader role
# assignment scoped to the resource group.
# =============================================================================

data "azurerm_client_config" "current" {}

locals {
  subscription_id = coalesce(var.azurevm_provider.subscription_id, data.azurerm_client_config.current.subscription_id)
  # Default the provider's discovery scope to the VM's own resource group.
  provider_resource_group = coalesce(var.azurevm_provider.resource_group, var.resource_group_name)

  # hub.providers.azureVM static config as CLI flags (same delivery as the
  # nutanix args in traefik/shared and the EC2 demo's custom_arguments). No
  # tenantID/clientID/clientSecret: DefaultAzureCredential -> managed identity.
  azurevm_provider_args = var.azurevm_provider.enabled ? concat(
    [
      "--hub.providers.azurevm=true",
      "--hub.providers.azurevm.subscriptionID=${local.subscription_id}",
      "--hub.providers.azurevm.resourceGroup=${local.provider_resource_group}",
      "--hub.providers.azurevm.ipMode=${var.azurevm_provider.ip_mode}",
      "--hub.providers.azurevm.exposedByDefault=${var.azurevm_provider.exposed_by_default}",
    ],
    var.azurevm_provider.default_rule != "" ? ["--hub.providers.azurevm.defaultRule=${var.azurevm_provider.default_rule}"] : [],
    var.azurevm_provider.constraints != "" ? ["--hub.providers.azurevm.constraints=${var.azurevm_provider.constraints}"] : [],
    var.azurevm_provider.refresh_seconds != null ? ["--hub.providers.azurevm.refreshSeconds=${var.azurevm_provider.refresh_seconds}"] : [],
    var.azurevm_provider.nsg_port_discovery ? ["--hub.providers.azurevm.nsgPortDiscovery=true"] : [],
  ) : []

  # Use extracted CLI arguments from Helm template (includes file provider if configured)
  # Filter out placeholder token arg to avoid duplicates with manual injection in Systemd unit
  cli_arguments = [
    for arg in module.config.extracted_cli_args_cloud :
    arg if !startswith(arg, "--hub.token=")
  ]

  # Merge standard env vars with explicit HUB_TOKEN injection (EC2 pattern)
  env_vars_list = concat(
    module.config.env_vars_list,
    module.config.traefik_hub_token != "" ? [{ name = "HUB_TOKEN", value = module.config.traefik_hub_token }] : []
  )

  # Normalize performance tuning with defaults
  performance_tuning = {
    limit_nofile        = coalesce(try(var.performance_tuning.limit_nofile, null), 500000)
    tcp_tw_reuse        = coalesce(try(var.performance_tuning.tcp_tw_reuse, null), 1)
    tcp_timestamps      = coalesce(try(var.performance_tuning.tcp_timestamps, null), 1)
    rmem_max            = coalesce(try(var.performance_tuning.rmem_max, null), 16777216)
    wmem_max            = coalesce(try(var.performance_tuning.wmem_max, null), 16777216)
    somaxconn           = coalesce(try(var.performance_tuning.somaxconn, null), 4096)
    netdev_max_backlog  = coalesce(try(var.performance_tuning.netdev_max_backlog, null), 4096)
    ip_local_port_range = coalesce(try(var.performance_tuning.ip_local_port_range, null), "1024 65535")
    gomaxprocs          = coalesce(try(var.performance_tuning.gomaxprocs, null), 0)
    gogc                = coalesce(try(var.performance_tuning.gogc, null), 100)
    numa_node           = coalesce(try(var.performance_tuning.numa_node, null), -1)
  }

  instance_key = "${var.vm_name}-1"

  user_data = templatefile("${path.module}/../cloud-init/cloud-init.tpl", {
    traefik_hub_version  = module.config.image_tag
    arch                 = "amd64"
    cli_arguments        = local.cli_arguments
    env_vars             = local.env_vars_list
    file_provider_config = var.file_provider_config
    extra_files          = var.extra_files
    performance_tuning   = local.performance_tuning
    otlp_address         = module.config.otlp_endpoint
    instance_name        = local.instance_key
    dashboard_config     = "" # Optional
    vip                  = "" # Optional
    keepalived_priority  = 100
    network_interface    = "eth0" # Azure Ubuntu default NIC name
    dns_traefiker        = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode  = var.enable_preview_mode
    preview_image        = module.config.image_full
  })
}

resource "azurerm_public_ip" "traefik" {
  count = var.enable_public_ip ? 1 : 0

  name                = "${var.vm_name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "traefik" {
  name                = "${var.vm_name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.traefik[0].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "traefik" {
  # Gated on the config-known BOOL, not the id: the id is usually a same-run
  # resource attribute (unknown at plan), and count can't depend on those —
  # first-ever fresh apply of the azure demo failed exactly here (2026-07).
  count = var.enable_network_security_group ? 1 : 0

  network_interface_id      = azurerm_network_interface.traefik.id
  network_security_group_id = var.network_security_group_id
}

resource "azurerm_linux_virtual_machine" "traefik" {
  name                = local.instance_key
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size

  network_interface_ids = [azurerm_network_interface.traefik.id]

  admin_username = var.admin_username
  admin_password = var.admin_password
  # Demo-grade: the spoke VM is driven over password auth (admin_password var +
  # cloud-init user-data) — no per-demo SSH key wiring exists. Suppressed inline
  # rather than repo-wide (.tfsec.yml) to keep the blast radius to this resource.
  #tfsec:ignore:azure-compute-disable-password-authentication
  disable_password_authentication = false

  custom_data = base64encode(local.user_data)

  # DefaultAzureCredential inside the container resolves this identity via
  # IMDS (reachable thanks to --network host in the cloud-init's docker run).
  identity {
    type = "SystemAssigned"
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

  tags = merge(
    var.extra_tags,
    # Self-register the Traefik VM's own dashboard via its azureVM provider
    # (-> dashboard@azurevm). Disable when the dashboard is advertised another
    # way (e.g. a file-rule uplink): without traefik.enable the VM isn't
    # self-discovered at all, so no redundant self-router appears.
    var.enable_dashboard_discovery ? {
      "traefik.enable"                                           = "true"
      "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
      "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
      "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
    } : {}
  )
}

# Reader on the resource group: the least privilege the azureVM provider needs
# to list VMs, NICs, public IPs, and NSGs in its discovery scope.
resource "azurerm_role_assignment" "reader" {
  count = var.enable_reader_role ? 1 : 0

  scope                = "/subscriptions/${local.subscription_id}/resourceGroups/${local.provider_resource_group}"
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_virtual_machine.traefik.identity[0].principal_id
}

# =============================================================================
# Shared Configuration Module - Azure VM
# =============================================================================
# Azure VM uses extracted config from helm template (extract_config=true),
# exactly like EC2. Shared variables are defined here alongside the module
# instantiation.
# =============================================================================

module "config" {
  source = "../shared"

  # Extract config - the VM needs CLI args, env vars from Helm template
  extract_config = true

  # Feature Flags
  enable_api_gateway    = var.enable_api_gateway
  enable_ai_gateway     = var.enable_ai_gateway
  enable_mcp_gateway    = var.enable_mcp_gateway
  enable_api_management = false # K8s only
  enable_offline_mode   = var.enable_offline_mode
  enable_preview_mode   = var.enable_preview_mode
  enable_debug          = var.enable_debug

  # Versions & Images
  traefik_chart_version   = var.traefik_chart_version
  traefik_tag             = var.traefik_tag
  traefik_hub_tag         = var.traefik_hub_tag
  traefik_hub_preview_tag = var.traefik_hub_preview_tag
  custom_image_registry   = var.custom_image_registry
  custom_image_repository = var.custom_image_repository
  custom_image_tag        = var.custom_image_tag

  # Observability
  log_level                    = var.log_level
  otlp_address                 = var.otlp_address
  otlp_service_name            = var.otlp_service_name
  enable_otlp_access_logs      = var.enable_otlp_access_logs
  enable_otlp_application_logs = var.enable_otlp_application_logs
  enable_otlp_metrics          = var.enable_otlp_metrics
  enable_otlp_traces           = var.enable_otlp_traces
  enable_prometheus            = var.enable_prometheus
  enable_access_logs           = var.enable_access_logs

  # Plugins & Extensions
  custom_plugins       = var.custom_plugins
  custom_ports         = var.custom_ports
  custom_arguments     = concat(var.custom_arguments, local.azurevm_provider_args)
  custom_envs          = var.custom_envs
  file_provider_config = var.file_provider_config
  file_provider_path   = var.file_provider_path

  # Licensing
  traefik_hub_token = var.traefik_hub_token

  # Dashboard
  enable_dashboard      = var.enable_dashboard
  dashboard_insecure    = var.dashboard_insecure
  dashboard_entrypoints = var.dashboard_entrypoints
  dashboard_match_rule  = var.dashboard_match_rule

  # Providers
  multicluster_provider = var.multicluster_provider
}
