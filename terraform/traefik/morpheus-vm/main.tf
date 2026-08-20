# =============================================================================
# HPE Morpheus VM Traefik Deployment — the multicluster CHILD on Morpheus
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2, traefik/azure-vm and
# traefik/vsphere-vm. The instance itself (plus its Morpheus placement lookups
# and the bootstrap task/workflow DELIVERY infra) lives in the shared
# compute/morpheus/vm module — the same module apps/whoami/morpheus composes,
# exactly like traefik/ec2 + whoami/ec2 share compute/aws/ec2. One
# hpe_morpheus_instance on an MVM cloud (MVM — the KVM compute type of HPE VM
# Essentials / HVM; config_hvm is the KVM placement) runs the Hub image; its
# morpheus provider (--hub.providers.morpheus) discovers workload instances by
# their `traefik.*` instance TAGS (dotted name/value pairs — the cloud-style
# label model).
# Morpheus has NO ambient identity for the gateway to lean on, so the provider
# authenticates explicitly: an API access token (var.morpheus_access_token,
# preferred) OR username+password (var.morpheus_provider.username +
# var.morpheus_password) — the gateway's Init enforces exactly one.
#
# BOOTSTRAP: the HPE/hpe terraform provider has no user-data passthrough on
# its instance resource (verified against the v1.5.0 schema; neither did
# gomorpheus), so the composed traefik/cloud-init payload is
# CONVERTED (yamldecode below: write_files -> heredocs, runcmd -> tolerated
# sequential entries — cloud-init's own semantics) into a shell script HERE and
# handed to the compute module as opaque user_data; the module delivers it as a
# Morpheus shell-script task in a postProvision provisioning workflow, executed
# on the instance by the Morpheus agent.
# =============================================================================

locals {
  # hub.providers.morpheus static config as CLI flags (same delivery as the
  # vsphere/azureVM args in the sibling modules). Endpoint must be a full URL
  # including the scheme — the provider's Init rejects a bare host.
  morpheus_provider_args = var.morpheus_provider.enabled ? concat(
    [
      "--hub.providers.morpheus=true",
      "--hub.providers.morpheus.endpoint=${var.morpheus_provider.endpoint}",
      "--hub.providers.morpheus.ipMode=${var.morpheus_provider.ip_mode}",
      "--hub.providers.morpheus.exposedByDefault=${var.morpheus_provider.exposed_by_default}",
    ],
    # Exactly one auth method (Init enforces token XOR user/pass) — see the
    # precondition on terraform_data.gateway_provider_auth below.
    var.morpheus_access_token != "" ? [
      "--hub.providers.morpheus.accessToken=${var.morpheus_access_token}",
      ] : [
      "--hub.providers.morpheus.username=${var.morpheus_provider.username}",
      "--hub.providers.morpheus.password=${var.morpheus_password}",
    ],
    var.morpheus_provider.insecure_skip_verify ? ["--hub.providers.morpheus.insecureSkipVerify=true"] : [],
    var.morpheus_provider.default_rule != "" ? ["--hub.providers.morpheus.defaultRule=${var.morpheus_provider.default_rule}"] : [],
    var.morpheus_provider.constraints != "" ? ["--hub.providers.morpheus.constraints=${var.morpheus_provider.constraints}"] : [],
    var.morpheus_provider.refresh_seconds != null ? ["--hub.providers.morpheus.refreshSeconds=${var.morpheus_provider.refresh_seconds}"] : [],
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
    # Gate on the CALLER's var.otlp_address, not module.config.otlp_endpoint: the
    # latter falls back to "http://opentelemetry-collector:4318" and is NEVER empty,
    # so this condition was always true -- every deployment that did not configure
    # OTLP still blocked in cloud-init for the gate's full 30-minute budget (180
    # rounds x 10s) waiting for a collector that was never going to exist.
    collector_gate = var.otlp_address != "" ? templatefile("${path.module}/../../cloud-init-snippets/otlp-collector-gate.sh.tpl", { otlp_address = module.config.otlp_endpoint, rounds = 180, verify_tls = false }) : ""
    # Inert here: only the docker-provider leg needs the socket bound in or extra
    # containers provisioned. The shared template requires both keys regardless --
    # templatefile hard-errors on a key the template uses but the caller omits.
    # Not offered by this module: only a guest whose ROOT is too small for the container
    # engine needs one (a KubeVirt containerDisk is fixed at the image's virtual size).
    # The key must still be passed -- templatefile hard-errors on a key the template uses
    # but the caller omits, which is how adding it to ONE of the nine renderers broke the
    # other eight.
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
    # Feeds the template's own %{ if otlp_address != "" } guard: pass the caller's
    # raw value so the gate block only renders when OTLP is actually configured.
    otlp_address        = var.otlp_address
    instance_name       = local.instance_key
    dashboard_config    = "" # Optional
    vip                 = "" # Optional
    keepalived_priority = 100
    network_interface   = "enp1s0" # virtio NIC name on Ubuntu under KVM/MVM — only the keepalived/vip path reads it (disabled here)
    dns_traefiker       = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode = var.enable_preview_mode
    preview_image       = module.config.image_full
  })

  # The cloud-config -> shell adapter (see the header): the composed template's
  # write_files + runcmd become the bootstrap script; its users/chpasswd access
  # conveniences are NOT applied (Morpheus provisioning covers access).
  cloud_config = yamldecode(local.user_data)

  bootstrap = join("\n", concat(
    [
      "#!/usr/bin/env bash",
      "# Generated from traefik/cloud-init's #cloud-config (see main.tf).",
      "set -u",
      "",
    ],
    flatten([for i, f in try(local.cloud_config.write_files, []) : [
      "mkdir -p \"$(dirname '${f.path}')\"",
      "cat > '${f.path}' <<'TF_EOF_${i}'",
      trimsuffix(f.content, "\n"),
      "TF_EOF_${i}",
      "chown ${try(f.owner, "root:root")} '${f.path}'",
      "chmod ${try(f.permissions, "0644")} '${f.path}'",
      "",
    ]]),
    # Each runcmd entry runs in a subshell and a failure is logged, not fatal —
    # matching cloud-init's runcmd semantics (no -e across entries).
    flatten([for i, c in try(local.cloud_config.runcmd, []) : [
      "(",
      trimsuffix(c, "\n"),
      ") || echo \"WARN: runcmd entry ${i} exited non-zero\"",
      "",
    ]]),
    # Critical postcondition — fail LOUD. The tolerant wrapper above is correct for the
    # genuinely-optional runcmd steps (node_exporter, the iptables open, the sshd tweaks), but
    # it also swallows the failure of the ONE step the gateway cannot live without: installing
    # Docker and pulling the image it runs as a container. When that step failed silently (a
    # broken apt inside a swallowed subshell — exactly what a null-DNS boot produced, 2026-07-17),
    # the bootstrap "succeeded", terraform saw a green task, and the gateway crash-looped on
    # `203/EXEC` (/usr/bin/docker missing) undiscovered for 40 minutes until the poll window blew.
    # Asserting the end-state here makes exec-task.sh see a non-zero exit and terraform fail FAST
    # with a real message. Unwrapped on purpose — this is the line that must abort the bootstrap.
    [
      "command -v docker >/dev/null 2>&1 || { echo 'FATAL: docker not installed — the gateway runs as a container and cannot start without it (check the docker-install step above for a swallowed apt/network failure)'; exit 1; }",
      "docker image inspect '${module.config.image_full}' >/dev/null 2>&1 || { echo 'FATAL: gateway image ${module.config.image_full} was not pulled — cannot start the gateway'; exit 1; }",
      "",
    ],
    ["exit 0"],
  ))

  # Self-register the Traefik instance's own dashboard via its morpheus provider
  # (-> dashboard@morpheus) — the tag-based siblings' trick, as instance tags.
  # Disable when the dashboard is advertised another way (e.g. a file-rule
  # uplink): without traefik.enable the instance isn't self-discovered at all.
  self_labels = var.enable_dashboard_discovery ? {
    "traefik.enable"                                           = "true"
    "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
    "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
    "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
  } : {}

  traefik_labels = merge(local.self_labels, var.extra_labels)
}

# The gateway's morpheus provider auth check. This USED TO be a precondition on
# hpe_morpheus_instance.traefik's lifecycle, but the instance now lives in the
# role-agnostic compute/morpheus/vm module — which knows nothing about the Hub
# provider's credentials — so the check relocates here (a no-op terraform_data
# state object) to keep the SAME plan-time hard failure. The NIC-type
# precondition, being pure infra, stayed with the instance in the module.
resource "terraform_data" "gateway_provider_auth" {
  lifecycle {
    precondition {
      condition     = !var.morpheus_provider.enabled || (var.morpheus_access_token != "") != (var.morpheus_provider.username != "" && var.morpheus_password != "")
      error_message = "Configure exactly ONE auth method for the morpheus provider: morpheus_access_token OR morpheus_provider.username + morpheus_password (the gateway's Init enforces token XOR user/pass)."
    }
  }
}

# =============================================================================
# Shared Compute Module — Morpheus VM
# =============================================================================
# The instance + its Morpheus placement lookups + the bootstrap task/workflow
# delivery infra. One app (the gateway), one replica; tags carry the Traefik
# labels; the bootstrap SCRIPT (local.bootstrap) is handed in as opaque
# user_data; the optional static-IP pin rides private_ips. The bootstrap
# task/workflow are named "<vm_name>-traefik-bootstrap" (unchanged).
# =============================================================================

module "compute" {
  source = "../../compute/morpheus/vm"

  cloud                        = var.cloud
  group                        = var.group
  instance_type                = var.instance_type
  instance_layout              = var.instance_layout
  instance_layout_version      = var.instance_layout_version
  plan                         = var.plan
  plan_provision_type          = var.plan_provision_type
  resource_pool_name           = var.resource_pool_name
  network                      = var.network
  network_interface_type_id    = var.network_interface_type_id
  root_volume                  = var.root_volume
  instance_type_id             = var.instance_type_id
  instance_layout_id           = var.instance_layout_id
  resource_pool_id             = var.resource_pool_id
  computed_placement_ids       = var.computed_placement_ids
  enable_provisioning_workflow = var.enable_provisioning_workflow

  apps = {
    (var.vm_name) = {
      replicas       = 1
      user_data      = local.bootstrap
      bootstrap_name = "${var.vm_name}-traefik-bootstrap"
      tags           = local.traefik_labels
      private_ips    = var.private_ip != "" ? [var.private_ip] : []
    }
  }
}

# =============================================================================
# Shared Configuration Module - Morpheus VM
# =============================================================================
# Morpheus VM uses extracted config from helm template (extract_config=true),
# exactly like EC2, Azure VM and vSphere VM. Shared variables are defined in
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
  custom_arguments     = concat(var.custom_arguments, local.morpheus_provider_args)
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
