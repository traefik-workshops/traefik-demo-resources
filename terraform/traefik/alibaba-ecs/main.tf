# =============================================================================
# Alibaba ECS Traefik Deployment — the multicluster CHILD on Alibaba Cloud ECS
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2, traefik/azure-vm and
# traefik/oci-vm. One ECS instance runs the Hub image as a docker container
# (the cloud-init preview-image path) with an INSTANCE RAM ROLE: the
# alibabaECS provider's default credential chain (env -> profile -> RAM role
# via metadata) picks up the role keylessly — no access keys on the VM (the
# 100.100.100.200 metadata endpoint works with --network host).
# =============================================================================

data "alicloud_regions" "current" {
  current = true
}

locals {
  # Default the provider's discovery scope to the instance's own region.
  provider_region = var.alibabaecs_provider.region_id != "" ? var.alibabaecs_provider.region_id : data.alicloud_regions.current.regions[0].id

  # hub.providers.alibabaECS static config as CLI flags (same delivery as the
  # oci flags in traefik/oci-vm). No accessKeyID/accessKeySecret: the default
  # credential chain resolves the instance RAM role via metadata.
  alibabaecs_provider_args = var.alibabaecs_provider.enabled ? concat(
    [
      "--hub.providers.alibabaECS=true",
      "--hub.providers.alibabaECS.regionID=${local.provider_region}",
      "--hub.providers.alibabaECS.ipMode=${var.alibabaecs_provider.ip_mode}",
      "--hub.providers.alibabaECS.exposedByDefault=${var.alibabaecs_provider.exposed_by_default}",
    ],
    var.alibabaecs_provider.endpoint != "" ? ["--hub.providers.alibabaECS.endpoint=${var.alibabaecs_provider.endpoint}"] : [],
    var.alibabaecs_provider.default_rule != "" ? ["--hub.providers.alibabaECS.defaultRule=${var.alibabaecs_provider.default_rule}"] : [],
    var.alibabaecs_provider.constraints != "" ? ["--hub.providers.alibabaECS.constraints=${var.alibabaecs_provider.constraints}"] : [],
    var.alibabaecs_provider.refresh_seconds != null ? ["--hub.providers.alibabaECS.refreshSeconds=${var.alibabaecs_provider.refresh_seconds}"] : [],
    var.alibabaecs_provider.security_group_port_discovery ? ["--hub.providers.alibabaECS.securityGroupPortDiscovery=true"] : [],
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
    network_interface    = "eth0" # Alibaba Ubuntu default NIC name
    dns_traefiker        = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode  = var.enable_preview_mode
    preview_image        = module.config.image_full
  })

  image_id = var.image_id != "" ? var.image_id : data.alicloud_images.ubuntu.images[0].id
}

# Latest Ubuntu 24.04 public image — the same OS the azure-vm/oci-vm siblings
# run (the cloud-init installs docker via apt).
data "alicloud_images" "ubuntu" {
  owners      = "system"
  name_regex  = "^ubuntu_24_04_x64"
  most_recent = true
}

# The alibabaECS provider's credential: an instance RAM role (trusted by
# ecs.aliyuncs.com) with read-only ECS Describe rights — covers
# DescribeInstances and the security-group reads securityGroupPortDiscovery
# needs. RAM names are account-global — disable when the demo already created
# them under the same vm_name elsewhere.
resource "alicloud_ram_role" "traefik" {
  count = var.enable_ram_role ? 1 : 0

  role_name   = "${var.vm_name}-alibabaecs-role"
  description = "Traefik Hub alibabaECS provider discovery (read-only ECS)"

  assume_role_policy_document = jsonencode({
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["ecs.aliyuncs.com"]
        }
      }
    ]
    Version = "1"
  })
}

resource "alicloud_ram_policy" "traefik" {
  count = var.enable_ram_role ? 1 : 0

  policy_name = "${var.vm_name}-alibabaecs-policy"
  description = "Read-only ECS discovery for the Traefik Hub alibabaECS provider"

  policy_document = jsonencode({
    Statement = [
      {
        Action   = ["ecs:Describe*"]
        Effect   = "Allow"
        Resource = ["*"]
      }
    ]
    Version = "1"
  })
}

resource "alicloud_ram_role_policy_attachment" "traefik" {
  count = var.enable_ram_role ? 1 : 0

  role_name   = alicloud_ram_role.traefik[0].role_name
  policy_name = alicloud_ram_policy.traefik[0].policy_name
  policy_type = "Custom"
}

# Escape hatch mirroring traefik/oci-vm's enable_nsg: a security group opening
# the demo ports (incl. the :9443 uplink the parent dials) from
# security_group_source_cidr. Off by default — compute/alibaba/vpc's group
# already opens them.
resource "alicloud_security_group" "traefik" {
  count = var.enable_security_group ? 1 : 0

  security_group_name = "${var.vm_name}-sg"
  vpc_id              = var.vpc_id
}

resource "alicloud_security_group_rule" "ingress" {
  for_each = var.enable_security_group ? { for port in var.security_group_ingress_ports : tostring(port) => port } : {}

  type              = "ingress"
  ip_protocol       = "tcp"
  policy            = "accept"
  port_range        = "${each.value}/${each.value}"
  cidr_ip           = var.security_group_source_cidr
  security_group_id = alicloud_security_group.traefik[0].id
}

resource "alicloud_instance" "traefik" {
  instance_name   = local.instance_key
  instance_type   = var.instance_type
  image_id        = local.image_id
  vswitch_id      = var.vswitch_id
  security_groups = concat(var.security_group_ids, var.enable_security_group ? [alicloud_security_group.traefik[0].id] : [])

  system_disk_category = var.system_disk_category
  system_disk_size     = var.system_disk_size

  # internet_max_bandwidth_out > 0 is what allocates a public IP on Alibaba.
  internet_max_bandwidth_out = var.enable_public_ip ? 10 : 0

  user_data = base64encode(local.user_data)

  tags = merge(
    var.extra_tags,
    # Self-register the Traefik instance's own dashboard via its alibabaECS
    # provider (-> dashboard@alibabaecs). Disable when the dashboard is
    # advertised another way (e.g. a file-rule uplink): without traefik.enable
    # the instance isn't self-discovered at all, so no redundant self-router
    # appears.
    var.enable_dashboard_discovery ? {
      "traefik.enable"                                           = "true"
      "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
      "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
      "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
    } : {}
  )
}

# The keyless credential: the default chain's last stop is the attached role's
# metadata-served STS credentials.
resource "alicloud_ecs_ram_role_attachment" "traefik" {
  count = var.enable_ram_role ? 1 : 0

  ram_role_name = alicloud_ram_role.traefik[0].role_name
  instance_id   = alicloud_instance.traefik.id
}

# =============================================================================
# Shared Configuration Module - Alibaba ECS
# =============================================================================
# Alibaba ECS uses extracted config from helm template (extract_config=true),
# exactly like EC2, Azure VM and OCI VM. Shared variables are defined here
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
  custom_arguments     = concat(var.custom_arguments, local.alibabaecs_provider_args)
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
