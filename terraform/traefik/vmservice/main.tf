# =============================================================================
# VM Service Traefik Deployment — the multicluster CHILD on a vSphere VM the
# SUPERVISOR provisioned
# =============================================================================
# The same gateway as traefik/vsphere-vm (shared traefik/shared config extraction, shared
# traefik/cloud-init template, the same --hub.providers.vsphere flags), on a vSphere VM that
# terraform did NOT clone: a `VirtualMachine` object inside a vSphere Namespace, reconciled by
# the Supervisor's VM Service (vm-operator) from a content-library image, a VirtualMachineClass
# and the namespace's storage class and network. The cloud-init user-data rides in as a
# rawCloudConfig bootstrap Secret. The result is an ordinary vCenter VM, so everything the
# clone sibling says about the provider holds unchanged — explicit vCenter credentials,
# tag-based discovery, routing intent over configEndpoint.
#
# What changes for the CALLER: the guest address is assigned by the namespace network after
# power-on and is known only after apply (status.network.primaryIP4). A parent that dials
# this child's :9443 uplink cannot take the address from this module at plan time; feed it
# through a variable filled between two applies instead, and read it off `private_ips`.
# =============================================================================

locals {
  # hub.providers.vsphere static config as CLI flags (same delivery as the
  # azureVM/oci args in the sibling modules). Endpoint may be a bare vCenter
  # host — the provider applies the SDK defaults (https scheme, /sdk path).
  # hub.providers.vsphere static config as CLI flags. The provider discovers service
  # membership from vCenter TAGS (serviceNameCategoryKey) and takes its routers/services
  # from a base configuration pulled over configEndpoint (GitOps) or read from filename —
  # there are no per-VM label flags (constraints / exposedByDefault / defaultRule) any
  # more, because VMs no longer carry labels.
  vsphere_provider_args = var.vsphere_provider.enabled ? concat(
    [
      "--hub.providers.vsphere=true",
      "--hub.providers.vsphere.endpoint=${var.vsphere_provider.endpoint}",
      "--hub.providers.vsphere.username=${var.vsphere_provider.username}",
      "--hub.providers.vsphere.password=${var.vsphere_password}",
      "--hub.providers.vsphere.ipMode=${var.vsphere_provider.ip_mode}",
      "--hub.providers.vsphere.serviceNameCategoryKey=${var.vsphere_provider.service_name_category_key}",
    ],
    var.vsphere_provider.insecure_skip_verify ? ["--hub.providers.vsphere.insecureSkipVerify=true"] : [],
    var.vsphere_provider.datacenter != "" ? ["--hub.providers.vsphere.datacenter=${var.vsphere_provider.datacenter}"] : [],
    var.vsphere_provider.config_endpoint != "" ? ["--hub.providers.vsphere.configEndpoint=${var.vsphere_provider.config_endpoint}"] : [],
    var.vsphere_provider.config_insecure_skip_verify ? ["--hub.providers.vsphere.configTLS.insecureSkipVerify=true"] : [],
    var.vsphere_provider.filename != "" ? ["--hub.providers.vsphere.filename=${var.vsphere_provider.filename}"] : [],
    var.vsphere_provider.refresh_seconds != null ? ["--hub.providers.vsphere.refreshSeconds=${var.vsphere_provider.refresh_seconds}"] : [],
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

  api_version = "vmoperator.vmware.com/${var.api_version}"
  labels      = { "app.kubernetes.io/name" = var.vm_name }

  # The kubectl the wait script runs: pinned to the caller's kubeconfig + context, never the
  # machine-global current-context (a parallel standup repoints that mid-apply).
  kubectl = join(" ", compact([
    "kubectl",
    var.kubeconfig != "" ? "--kubeconfig ${var.kubeconfig}" : "",
    var.kubeconfig_context != "" ? "--context ${var.kubeconfig_context}" : "",
  ]))

  user_data = templatefile("${path.module}/../cloud-init/cloud-init.tpl", {
    # Shared cloud-init snippets, rendered here and injected pre-rendered
    # (templatefile has no include; see terraform/cloud-init-snippets/README.md).
    docker_install = file("${path.module}/../../cloud-init-snippets/docker-install.sh.tpl")
    # Gate on the CALLER's var.otlp_address, not module.config.otlp_endpoint: the
    # latter falls back to "http://opentelemetry-collector:4318" and is NEVER empty,
    # so this condition was always true -- every deployment that did not configure
    # OTLP still blocked in cloud-init for the gate's full 30-minute budget (180
    # rounds x 10s) waiting for a collector that was never going to exist.
    collector_gate       = var.otlp_address != "" ? templatefile("${path.module}/../../cloud-init-snippets/otlp-collector-gate.sh.tpl", { otlp_address = module.config.otlp_endpoint, rounds = 180, verify_tls = false }) : ""
    traefik_hub_version  = module.config.image_tag
    arch                 = "amd64"
    cli_arguments        = local.cli_arguments
    env_vars             = local.env_vars_list
    file_provider_config = var.file_provider_config
    extra_files          = var.extra_files
    # Not offered by this module: only a guest whose ROOT is too small for the container
    # engine needs one (a KubeVirt containerDisk is fixed at the image's virtual size).
    # The key must still be passed -- templatefile hard-errors on a key the template uses
    # but the caller omits, which is how adding it to ONE of the nine renderers broke the
    # other eight.
    data_disk           = null
    mount_docker_socket = var.mount_docker_socket
    ssh_public_key      = var.ssh_public_key
    extra_runcmd        = var.extra_runcmd
    performance_tuning  = local.performance_tuning
    # Feeds the template's own %{ if otlp_address != "" } guard: pass the caller's
    # raw value so the gate block only renders when OTLP is actually configured.
    otlp_address        = var.otlp_address
    instance_name       = local.instance_key
    dashboard_config    = "" # Optional
    vip                 = "" # Optional
    keepalived_priority = 100
    network_interface   = "ens192" # vmxnet3 NIC name on Ubuntu cloud images
    dns_traefiker       = { enabled = false, version = "v1.0.4", chart = "", unique_domain = false, domain = "", enable_airlines_subdomain = false, ip_override = "", proxied = false }
    enable_preview_mode = var.enable_preview_mode
    preview_image       = module.config.image_full
  })
}

# The gateway's cloud-init lives in a Secret: vm-operator's rawCloudConfig bootstrap reads the
# user-data out of a Secret key. Same shape as apps/whoami/vmservice.
resource "kubectl_manifest" "bootstrap" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "${local.instance_key}-bootstrap"
      namespace = var.namespace
      labels    = local.labels
    }
    stringData = { "user-data" = local.user_data }
  })
}

resource "kubectl_manifest" "vm" {
  # The Secret must exist before vm-operator reconciles the VM, or the bootstrap is
  # rejected and the guest powers on with no user-data — no Docker, no Traefik.
  depends_on = [kubectl_manifest.bootstrap]

  yaml_body = yamlencode({
    apiVersion = local.api_version
    kind       = "VirtualMachine"
    metadata = {
      name      = local.instance_key
      namespace = var.namespace
      labels    = local.labels
    }
    spec = merge(
      {
        className    = var.class_name
        imageName    = var.image_name
        storageClass = var.storage_class
        powerState   = "PoweredOn"
        bootstrap = {
          cloudInit = {
            rawCloudConfig = { name = "${local.instance_key}-bootstrap", key = "user-data" }
          }
        }
      },
      # Omitted = the namespace's default network. Named = one interface on that network.
      var.network_name != "" ? {
        network = { interfaces = [{ name = "eth0", network = { name = var.network_name } }] }
      } : {},
    )
  })
}

# Wait for the guest address and read it back. Ordered behind the VirtualMachine; on a
# destroy plan, or before the object exists, the script returns empty fields instead of
# failing — see scripts/vm-ip.sh.
data "external" "guest" {
  depends_on = [kubectl_manifest.vm]

  program = ["bash", "${path.module}/scripts/vm-ip.sh"]
  query = {
    kubectl   = local.kubectl
    namespace = var.namespace
    name      = local.instance_key
    timeout   = tostring(var.ip_wait_timeout)
  }
}

# =============================================================================
# Shared Configuration Module - VM Service VM
# =============================================================================
# The VM Service gateway uses extracted config from helm template (extract_config=true),
# exactly like EC2 and Azure VM. Shared variables are defined in variables.tf
# alongside the platform-specific ones.
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
  custom_arguments     = concat(var.custom_arguments, local.vsphere_provider_args)
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
