# =============================================================================
# Hyper-V VM Traefik Deployment — the multicluster CHILD on Hyper-V/SCVMM
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2, traefik/vsphere-vm and
# traefik/proxmox-vm. One VM built from the golden Ubuntu cloud-image parent
# (differencing VHDX + NoCloud seed, via compute/hyperv/vm) runs the Hub image,
# and guest discovery is the NATIVE first-party Hub Hyper-V provider, delivered
# as static-config CLI flags:
#   --hub.providers.hyperv.*        (vmmserver/port/username/password/...)
#
# THE PROVIDER TALKS TO SCVMM, NOT TO HYPER-V HOSTS. Standalone Hyper-V has no
# API and no tags; SCVMM is the estate plane — so discovery is ONE PowerShell
# round trip per poll over WinRM HTTPS to the VMM MANAGEMENT SERVER
# (Get-SCVirtualMachine), reading each VM's line-format traefik.* labels from
# its VMM Description and its addresses from VMM's adapter view (populated by
# the VMM host agent + the guest KVP daemon; the traefik.hyperv.ip label is the
# escape hatch for KVP-less guests). Hyper-V hosts need NO WinRM exposure to
# the gateway at all.
#
# Optional scoping — the enterprise delegation story: `cloud` (a VMM Cloud —
# the quota/delegation boundary) or `host_group` (a VMHostGroup path) scope one
# gateway to one slice of the estate. They are MUTUALLY EXCLUSIVE; both empty
# discovers the whole estate.
#
# WinRM has no ambient identity (no instance profile / managed identity), so
# the provider authenticates with an explicit account — var.hyperv_password is
# the one secret this module carries. Point it at a READ-ONLY credential: a
# member of VMM's "Read-Only Administrator" user role that can also open raw
# WinRS shells on the VMM server (non-Administrators need the A;;GXGR RootSDDL
# ACE there — Remote Management Users membership alone is NOT sufficient).
# =============================================================================

locals {
  # The native provider's static config as CLI flags (same delivery as the
  # ec2/azurevm/gce/proxmox sibling modules: --hub.providers.<name>.*). Its
  # services surface as <name>@hyperv. Flag surface verified against
  # feat/hyperv-provider @ b0abe6ef (hub/pkg/provider/hyperv/provider.go).
  hyperv_provider_args = var.hyperv_provider.enabled ? concat(
    [
      "--hub.providers.hyperv=true",
      "--hub.providers.hyperv.vmmserver=${var.hyperv_provider.vmm_server}",
      "--hub.providers.hyperv.port=${var.hyperv_provider.port}",
      "--hub.providers.hyperv.username=${var.hyperv_provider.username}",
      "--hub.providers.hyperv.password=${var.hyperv_password}",
      "--hub.providers.hyperv.insecureskipverify=${var.hyperv_provider.insecure_skip_verify}",
      "--hub.providers.hyperv.refreshseconds=${var.hyperv_provider.refresh_seconds}",
      "--hub.providers.hyperv.exposedbydefault=${var.hyperv_provider.exposed_by_default}",
      "--hub.providers.hyperv.ipmode=${var.hyperv_provider.ip_mode}",
    ],
    var.hyperv_provider.cloud != "" ? ["--hub.providers.hyperv.cloud=${var.hyperv_provider.cloud}"] : [],
    var.hyperv_provider.host_group != "" ? ["--hub.providers.hyperv.hostgroup=${var.hyperv_provider.host_group}"] : [],
    var.hyperv_provider.constraints != "" ? ["--hub.providers.hyperv.constraints=${var.hyperv_provider.constraints}"] : [],
    var.hyperv_provider.default_rule != "" ? ["--hub.providers.hyperv.defaultrule=${var.hyperv_provider.default_rule}"] : [],
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
    collector_gate = module.config.otlp_endpoint != "" ? templatefile("${path.module}/../../cloud-init-snippets/otlp-collector-gate.sh.tpl", { otlp_address = module.config.otlp_endpoint, rounds = 180 }) : ""
    # Not offered by this module: only a guest whose ROOT is too small for the
    # container engine needs one. The key must still be passed — templatefile
    # hard-errors on a key the template uses but the caller omits, which is how
    # adding it to ONE of the renderers broke the others.
    data_disk            = null
    mount_docker_socket  = var.mount_docker_socket
    ssh_public_key       = var.ssh_public_key
    extra_runcmd         = var.extra_runcmd
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
    network_interface    = "eth0" # hv_netvsc NIC name on Ubuntu cloud images (predictable naming doesn't rename netvsc)
    dns_traefiker        = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode  = var.enable_preview_mode
    preview_image        = module.config.image_full
  })

  # NoCloud network-config v2 — STATIC addressing (Hyper-V has no plan-readable
  # discovery, and the hub's `children` map needs this VM's uplink address at
  # PLAN time; static-by-design is what makes that single-pass).
  network_config = yamlencode({
    version = 2
    ethernets = {
      eth0 = merge(
        {
          addresses = [var.ip_address]
          routes    = [{ to = "default", via = var.gateway }]
        },
        length(var.dns_servers) > 0 ? { nameservers = { addresses = var.dns_servers } } : {},
      )
    }
  })

  # NO dashboard self-registration here, unlike traefik/proxmox-vm: self-labels
  # would need a VMM-side write (Set-SCVirtualMachine — a second connection and
  # a WRITE credential this module deliberately does not carry). Advertise the
  # dashboard over a file-rule uplink instead, which is what the demo does.
}

# =============================================================================
# The VM — the shared compute/hyperv/vm primitive
# =============================================================================
# One VM off the golden parent, running the rendered user-data above. The seed
# ISO build, the cidata-label assert and the recreate-on-payload-change all
# live in the module (they are infra); this caller only renders the user-data
# and the static network-config.
module "vm" {
  source = "../../compute/hyperv/vm"

  host_winrm       = var.host_winrm
  switch_name      = var.switch_name
  parent_vhdx_path = var.parent_vhdx_path
  workdir          = var.workdir
  num_cpus         = var.num_cpus
  memory           = var.memory

  instances = {
    (local.instance_key) = {
      user_data      = local.user_data
      network_config = local.network_config
      ip_address     = split("/", var.ip_address)[0]
    }
  }
}

# =============================================================================
# Shared Configuration Module - Hyper-V VM
# =============================================================================
# Hyper-V VM uses extracted config from helm template (extract_config=true),
# exactly like EC2, vSphere VM and Proxmox VM. Shared variables are defined in
# variables.tf alongside the platform-specific ones.
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
  custom_arguments     = concat(var.custom_arguments, local.hyperv_provider_args)
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
