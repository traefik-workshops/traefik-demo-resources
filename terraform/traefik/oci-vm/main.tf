# =============================================================================
# OCI VM Traefik Deployment — the multicluster CHILD on OCI Compute
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2, traefik/azure-vm and
# traefik/gce. One VM runs the Hub image as a docker container (the cloud-init
# preview-image path) and authenticates the oci provider as an INSTANCE
# PRINCIPAL (security/oci-instance-principal's dynamic group + policy — no API
# keys on the VM; IMDS works with --network host).
# =============================================================================

locals {
  # Default the provider's discovery scope to the VM's own compartment.
  provider_compartment = coalesce(var.oci_provider.compartment_id, var.compartment_id)

  # hub.providers.oci static config as CLI flags (same delivery as the azureVM
  # flags in traefik/azure-vm). No configFilePath/profile: useInstancePrincipal
  # resolves the VM's identity via IMDS.
  oci_provider_args = var.oci_provider.enabled ? concat(
    [
      "--hub.providers.oci=true",
      "--hub.providers.oci.compartmentID=${local.provider_compartment}",
      "--hub.providers.oci.ipMode=${var.oci_provider.ip_mode}",
      # Nutanix-style discovery: the provider only resolves instance IPs and groups
      # them by the service-name freeform tag, then merges them into the services
      # defined in this base-config file (routing/LB/strategy live there).
      "--hub.providers.oci.filename=${var.oci_provider.filename}",
      "--hub.providers.oci.serviceNameTagKey=${var.oci_provider.service_name_tag_key}",
    ],
    var.oci_provider.use_instance_principal ? ["--hub.providers.oci.useInstancePrincipal=true"] : [],
    var.oci_provider.region != "" ? ["--hub.providers.oci.region=${var.oci_provider.region}"] : [],
    var.oci_provider.refresh_seconds != null ? ["--hub.providers.oci.refreshSeconds=${var.oci_provider.refresh_seconds}"] : [],
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
    # Shared cloud-init snippets, rendered here and injected pre-rendered
    # (templatefile has no include; see terraform/cloud-init-snippets/README.md).
    docker_install = file("${path.module}/../../cloud-init-snippets/docker-install.sh.tpl")
    collector_gate = module.config.otlp_endpoint != "" ? templatefile("${path.module}/../../cloud-init-snippets/otlp-collector-gate.sh.tpl", { otlp_address = module.config.otlp_endpoint }) : ""
    # Inert here: only the docker-provider leg needs the socket bound in or extra
    # containers provisioned. The shared template requires both keys regardless --
    # templatefile hard-errors on a key the template uses but the caller omits.
    mount_docker_socket  = false
    ssh_public_key       = var.ssh_public_key
    extra_runcmd         = []
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
    network_interface    = "ens3" # OCI Ubuntu default NIC name
    dns_traefiker        = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode  = var.enable_preview_mode
    preview_image        = module.config.image_full
  })
}

# The oci provider's credential: instance principals via
# security/oci-instance-principal (dynamic group matching every instance in
# the compartment + policy). Identity resources are tenancy-wide with fixed
# names — disable when the demo already instantiated the module elsewhere.
module "instance_principal" {
  count  = var.enable_instance_principal ? 1 : 0
  source = "../../security/oci-instance-principal"

  compartment_id = var.compartment_id
  tenancy_id     = var.tenancy_id
  home_region    = var.home_region
}

# Escape hatch mirroring traefik/gce's enable_firewall: an NSG opening the
# demo ports (incl. the :9443 uplink the parent dials) intra-VCN. Off by
# default — compute/oracle/oke's security list already allows all intra-VCN
# traffic on its subnets.
resource "oci_core_network_security_group" "traefik" {
  count = var.enable_nsg ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.vm_name}-nsg"
}

resource "oci_core_network_security_group_security_rule" "ingress" {
  for_each = var.enable_nsg ? { for port in var.nsg_ingress_ports : tostring(port) => port } : {}

  network_security_group_id = oci_core_network_security_group.traefik[0].id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.nsg_source_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = each.value
      max = each.value
    }
  }
}

# The VM itself lives in the shared compute module (whoami/oci-vm composes the
# same one). Everything role-specific — the rendered cloud-init, the pinned
# private IP, the caller-owned NSG, and the dashboard self-registration tags —
# is computed here and passed in.
module "compute" {
  source = "../../compute/oracle/vm"

  name           = var.vm_name
  replicas       = 1
  compartment_id = var.compartment_id

  availability_domain = var.availability_domain
  subnet_id           = var.subnet_id
  nsg_ids             = concat(var.nsg_ids, var.enable_nsg ? [oci_core_network_security_group.traefik[0].id] : [])

  shape         = var.shape
  ocpus         = var.ocpus
  memory_in_gbs = var.memory_in_gbs
  vm_image_ocid = var.vm_image_ocid

  enable_public_ip = var.enable_public_ip
  private_ips      = var.private_ip != "" ? [var.private_ip] : []

  user_data = local.user_data

  freeform_tags = merge(
    var.extra_tags,
    # Self-register the Traefik VM's own dashboard via its oci provider
    # (-> dashboard@oci). Disable when the dashboard is advertised another
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

# =============================================================================
# Shared Configuration Module - OCI VM
# =============================================================================
# OCI VM uses extracted config from helm template (extract_config=true),
# exactly like EC2, Azure VM and GCE. Shared variables are defined here
# alongside the module instantiation.
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
  custom_arguments     = concat(var.custom_arguments, local.oci_provider_args)
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
