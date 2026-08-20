# =============================================================================
# GCE Traefik Deployment — the multicluster CHILD on Google Compute Engine
# =============================================================================
# Uses extracted config from traefik/shared (via Helm template) and the shared
# traefik/cloud-init template, exactly like traefik/ec2 and traefik/azure-vm.
# One VM runs the Hub image as a docker container (the cloud-init preview-image
# path) with an attached service account: the gce provider authenticates via
# Application Default Credentials (the metadata server works with
# --network host) and a roles/compute.viewer project binding.
#
# DISCOVERY CONTRACT (mirrors traefik/vsphere-vm): an instance carries ONLY a
# service name — the value of one GCE label (gce_provider.service_name_label,
# provider default `traefik-service`). All routing intent (routers, services,
# middlewares, uplinks) lives in ONE base configuration the provider loads from
# gce_provider.config_endpoint (a GitOps URL, e.g. the hub's git-config-server)
# or gce_provider.filename (a path on the gateway) — exactly one. Base services
# declare scheme/port but no servers; the provider injects one server per
# discovered instance.
# =============================================================================

data "google_client_config" "current" {}

locals {
  # Default the provider's discovery scope to the caller's project.
  project_id = coalesce(var.gce_provider.project_id, data.google_client_config.current.project)

  # hub.providers.gce static config as CLI flags (same delivery as the azureVM
  # flags in traefik/azure-vm). The provider follows the vsphere contract: an
  # instance carries ONLY a service name (the value of its service_name_label
  # GCE label), and the routing intent comes from ONE base configuration —
  # polled from config_endpoint (GitOps) or read from filename, exactly one.
  # No credentialsFile/credentialsJSON: ADC resolves the VM's attached service
  # account.
  gce_provider_args = var.gce_provider.enabled ? concat(
    [
      "--hub.providers.gce=true",
      "--hub.providers.gce.projectID=${local.project_id}",
      "--hub.providers.gce.ipMode=${var.gce_provider.ip_mode}",
    ],
    length(var.gce_provider.zones) > 0 ? ["--hub.providers.gce.zones=${join(",", var.gce_provider.zones)}"] : [],
    var.gce_provider.service_name_label != "" ? ["--hub.providers.gce.serviceNameLabel=${var.gce_provider.service_name_label}"] : [],
    var.gce_provider.config_endpoint != "" ? ["--hub.providers.gce.configEndpoint=${var.gce_provider.config_endpoint}"] : [],
    var.gce_provider.config_insecure_skip_verify ? ["--hub.providers.gce.configTLS.insecureSkipVerify=true"] : [],
    var.gce_provider.filename != "" ? ["--hub.providers.gce.filename=${var.gce_provider.filename}"] : [],
    var.gce_provider.refresh_seconds != null ? ["--hub.providers.gce.refreshSeconds=${var.gce_provider.refresh_seconds}"] : [],
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
    network_interface   = "ens4" # GCE Ubuntu default NIC name
    dns_traefiker       = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode = var.enable_preview_mode
    preview_image       = module.config.image_full
  })

  # NO metadata self-registration: the gce provider reads no per-VM Traefik
  # labels or metadata blobs any more — an instance can only carry a service
  # name via its service_name_label GCE label, and this gateway VM carries
  # none. Advertise the dashboard through the base configuration instead
  # (a router on api@internal), which is where all routing intent lives.
}

# ADC inside the container resolves this identity via the metadata server
# (reachable thanks to --network host in the cloud-init's docker run).
# The account_id carries a per-execution suffix, and that is load-bearing. GCP does not
# release a deleted service-account name immediately -- recreating one with the same id
# shortly after a destroy returns
#   Error 409: Service account traefik-gce already exists ... alreadyExists
# even though `gcloud iam service-accounts list` shows nothing (verified: a teardown
# reported clean, and the very next `make up` 409'd on this exact name). Google's own
# guidance is not to reuse deleted service-account names; a fresh id per run obeys it and
# removes a whole class of un-rebuildable-for-30-days failures. Same reasoning as the
# Identity Toolkit API key in demos/gcp-unified-ingress/identity.tf.
resource "random_id" "sa_suffix" {
  byte_length = 3
}

resource "google_service_account" "traefik" {
  account_id   = "${var.service_account_id}-${random_id.sa_suffix.hex}"
  display_name = "Traefik Hub gce provider identity (${var.vm_name})"
}

# compute.viewer on the project: the least privilege the gce provider needs to
# list instances (metadata, labels, IPs) and firewall rules in its discovery
# scope.
resource "google_project_iam_member" "viewer" {
  count = var.enable_viewer_role ? 1 : 0

  project = local.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.traefik.email}"
}

# The VM (and its firewall) live in the shared compute/gcp/vm module. This
# caller keeps everything role-specific: the rendered cloud-init (built above
# into local.user_data), the service account, and the compute.viewer binding.
# The compute module just materializes the instance.
module "compute" {
  source = "../../compute/gcp/vm"

  # The gce provider polls the compute API at boot via ADC. Order the VM after
  # the roles/compute.viewer binding so the role has been granted before the
  # container starts — otherwise the provider races IAM propagation and throws
  # transient 403s until it self-heals.
  depends_on = [google_project_iam_member.viewer]

  instances = {
    (local.instance_key) = {
      metadata   = { user-data = local.user_data }
      labels     = var.extra_labels
      network_ip = var.private_ip
    }
  }

  machine_type     = var.machine_type
  zone             = var.zone
  vm_image         = var.vm_image
  network          = var.network
  subnetwork       = var.subnetwork
  enable_public_ip = var.enable_public_ip
  tags             = [var.vm_name]

  service_account = {
    email = google_service_account.traefik.email
    # cloud-platform + IAM roles is Google's recommended scoping; the narrow
    # legacy scopes double-limit what the viewer role already restricts.
    scopes = ["cloud-platform"]
  }

  # Open the demo ports (incl. the :9443 uplink the parent dials) intra-network
  # (mirrors compute/azure/vnet's NSG + extra_ingress_ports idea — GCP firewalls
  # are VPC-scoped, so the rule lives with the VM it targets).
  enable_firewall        = var.enable_firewall
  firewall_ports         = [for port in var.firewall_ports : tostring(port)]
  firewall_source_ranges = var.firewall_source_ranges
}

# =============================================================================
# Shared Configuration Module - GCE
# =============================================================================
# GCE uses extracted config from helm template (extract_config=true), exactly
# like EC2 and Azure VM. Shared variables are defined here alongside the
# module instantiation.
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
  custom_arguments     = concat(var.custom_arguments, local.gce_provider_args)
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
