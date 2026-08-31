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
# routing intent read from each workload VM's Notes (a line-format traefik label block).
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
  # The provider reads each VM's routing intent from its Notes (a line-format
  # traefik.<key>=<value> block), so the flags are the label-provider set:
  # exposedByDefault / constraints / defaultRule, like the proxmox sibling.
  vsphere_provider_args = var.vsphere_provider.enabled ? concat(
    [
      "--hub.providers.vsphere=true",
      "--hub.providers.vsphere.endpoint=${var.vsphere_provider.endpoint}",
      "--hub.providers.vsphere.username=${var.vsphere_provider.username}",
      "--hub.providers.vsphere.password=${var.vsphere_password}",
      "--hub.providers.vsphere.ipMode=${var.vsphere_provider.ip_mode}",
      "--hub.providers.vsphere.exposedByDefault=${var.vsphere_provider.exposed_by_default}",
    ],
    var.vsphere_provider.insecure_skip_verify ? ["--hub.providers.vsphere.insecureSkipVerify=true"] : [],
    var.vsphere_provider.datacenter != "" ? ["--hub.providers.vsphere.datacenter=${var.vsphere_provider.datacenter}"] : [],
    var.vsphere_provider.constraints != "" ? ["--hub.providers.vsphere.constraints=${var.vsphere_provider.constraints}"] : [],
    var.vsphere_provider.default_rule != "" ? ["--hub.providers.vsphere.defaultRule=${var.vsphere_provider.default_rule}"] : [],
    var.vsphere_provider.refresh_seconds != null ? ["--hub.providers.vsphere.refreshSeconds=${var.vsphere_provider.refresh_seconds}"] : [],
  ) : []

  # hub.providers.vmoperator static config as CLI flags. The provider reads each
  # VM Service VM's routing intent from ONE annotation on its VirtualMachine CR
  # (label_annotation, default traefik.io/config) via the Supervisor API, with a
  # namespace-scoped ServiceAccount token. TOKEN FILE ONLY, never an inline token
  # flag: every CLI argument lands in a world-readable systemd ExecStart line, so
  # the credential must ride a file (deliver it via extra_files to a path under
  # /data — in preview mode only /data and /etc/traefik-hub/dynamic are mounted
  # into the container).
  vmoperator_provider_args = var.vmoperator_provider.enabled ? concat(
    [
      "--hub.providers.vmoperator=true",
      "--hub.providers.vmoperator.endpoint=${var.vmoperator_provider.endpoint}",
      "--hub.providers.vmoperator.tokenFile=${var.vmoperator_provider.token_file}",
      "--hub.providers.vmoperator.exposedByDefault=${var.vmoperator_provider.exposed_by_default}",
    ],
    var.vmoperator_provider.insecure_skip_verify ? ["--hub.providers.vmoperator.tls.insecureSkipVerify=true"] : [],
    length(var.vmoperator_provider.namespaces) > 0 ? ["--hub.providers.vmoperator.namespaces=${join(",", var.vmoperator_provider.namespaces)}"] : [],
    var.vmoperator_provider.constraints != "" ? ["--hub.providers.vmoperator.constraints=${var.vmoperator_provider.constraints}"] : [],
    var.vmoperator_provider.default_rule != "" ? ["--hub.providers.vmoperator.defaultRule=${var.vmoperator_provider.default_rule}"] : [],
    var.vmoperator_provider.label_annotation != "" ? ["--hub.providers.vmoperator.labelAnnotation=${var.vmoperator_provider.label_annotation}"] : [],
    var.vmoperator_provider.api_version != "" ? ["--hub.providers.vmoperator.apiVersion=${var.vmoperator_provider.api_version}"] : [],
    var.vmoperator_provider.refresh_seconds != null ? ["--hub.providers.vmoperator.refreshSeconds=${var.vmoperator_provider.refresh_seconds}"] : [],
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
  # vSphere 8U2's WCP serves only v1alpha1, whose VirtualMachine predates spec.bootstrap
  # (cloud-init rides spec.vmMetadata over the CloudInit transport, powerState is lowercase).
  is_v1a1 = var.api_version == "v1alpha1"
  labels  = { "app.kubernetes.io/name" = var.vm_name }

  # spec.imageName is the VirtualMachineImage RESOURCE name and is IMMUTABLE. v1alpha2+ names the
  # image by var.image_name (resolves to itself); v1alpha1 names it vmi-<hash> and carries
  # var.image_name only in status.imageName. Resolve up front so the VM is created correct.
  resolved_image = try(data.external.image.result.name, var.image_name)

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

# Resolve var.image_name -> the VirtualMachineImage RESOURCE name (see local.resolved_image).
# Published to the namespace before terraform runs, so it exists at plan; a miss falls back to
# var.image_name (also the destroy-plan case).
data "external" "image" {
  program = ["bash", "${path.module}/scripts/resolve-image.sh"]
  query = {
    kubectl    = local.kubectl
    namespace  = var.namespace
    image_name = var.image_name
  }
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

  # v1alpha1 (vSphere 8U2) and v1alpha2+ (VCF 9) have DIFFERENT VirtualMachine schemas, so the
  # whole body is version-split at yamlencode (two strings unify where two differently-shaped
  # objects would not). Only the spec differs: v1alpha1 rides cloud-init on spec.vmMetadata
  # (Secret + CloudInit transport) with the lowercase powerState and a named net on
  # spec.networkInterfaces; v1alpha2+ uses spec.bootstrap.cloudInit.rawCloudConfig, PoweredOn and
  # spec.network.interfaces. The same "${local.instance_key}-bootstrap" Secret feeds both.
  yaml_body = local.is_v1a1 ? yamlencode({
    apiVersion = local.api_version
    kind       = "VirtualMachine"
    metadata   = { name = local.instance_key, namespace = var.namespace, labels = local.labels }
    spec = merge(
      {
        className    = var.class_name
        imageName    = local.resolved_image
        storageClass = var.storage_class
        powerState   = "poweredOn"
        vmMetadata   = { secretName = "${local.instance_key}-bootstrap", transport = "CloudInit" }
      },
      var.network_name != "" ? {
        networkInterfaces = [{ networkName = var.network_name, networkType = "vsphere-distributed" }]
      } : {},
    )
    }) : yamlencode({
    apiVersion = local.api_version
    kind       = "VirtualMachine"
    metadata   = { name = local.instance_key, namespace = var.namespace, labels = local.labels }
    spec = merge(
      {
        className    = var.class_name
        imageName    = local.resolved_image
        storageClass = var.storage_class
        powerState   = "PoweredOn"
        bootstrap    = { cloudInit = { rawCloudConfig = { name = "${local.instance_key}-bootstrap", key = "user-data" } } }
      },
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
  custom_arguments     = concat(var.custom_arguments, local.vsphere_provider_args, local.vmoperator_provider_args)
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
