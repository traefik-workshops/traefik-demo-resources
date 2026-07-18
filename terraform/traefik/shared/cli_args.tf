# =============================================================================
# CLI arguments appended to the Traefik command (additionalArguments).
# =============================================================================
# Each cli_args_* local contributes a (possibly empty) list of flags driven
# by a feature toggle. They concat into local.additional_arguments, which is
# wired into helm_values.additionalArguments (see helm_values.tf).
# =============================================================================

locals {
  cli_args_debug = var.enable_debug ? ["--api.debug=true"] : []

  # The file provider serves the BAKED dynamic config (file_provider_config) — the well-configured
  # path, identical to the pre-GitOps behavior (directory only, no watch: a baked file never
  # changes without a VM rebuild).
  cli_args_file_provider = var.file_provider_config != "" ? [
    "--providers.file.directory=${var.file_provider_path}",
  ] : []

  # GitOps (the degraded fallback for constrained platforms — OCI/vSphere/Nutanix/GCE) delivers the
  # dynamic config via the HTTP provider, NOT a file: the gateway POLLS gitops_endpoint (a raw
  # dynamic.yaml served by the hub git-config-server) and Traefik hot-reloads on its own
  # pollInterval — no VM-side sync script, no file watch, no boot gate. Uplinks ride through
  # unchanged: the http provider decodes the body with the same YAML decoder + inline ext.HTTP
  # embed as the file provider. tls.insecureSkipVerify is for lab-cert hosts (morpheus); the public
  # clouds trust git.<domain>.
  cli_args_http_provider = var.enable_gitops_config ? concat(
    [
      "--providers.http.endpoint=${var.gitops_endpoint}",
      "--providers.http.pollInterval=${var.gitops_poll_interval}",
    ],
    var.gitops_insecure_skip_verify ? ["--providers.http.tls.insecureSkipVerify=true"] : [],
  ) : []

  # Nutanix provider CLI arguments (generated from shared config).
  cli_args_nutanix = var.nutanix_provider.enabled ? concat(
    # Enable Nutanix provider
    ["--hub.providers.nutanixPrismCentral"],

    # Required arguments
    ["--hub.providers.nutanixPrismCentral.endpoint=${var.nutanix_provider.endpoint}"],

    # Authentication (use API key OR username/password)
    var.nutanix_provider.api_key != "" ? [
      "--hub.providers.nutanixPrismCentral.apiKey=${var.nutanix_provider.api_key}"
      ] : [
      "--hub.providers.nutanixPrismCentral.username=${var.nutanix_provider.username}",
      "--hub.providers.nutanixPrismCentral.password=${var.nutanix_provider.password}"
    ],

    # Optional TLS configuration
    var.nutanix_provider.insecure_skip_verify ? [
      "--hub.providers.nutanixPrismCentral.tls.insecureSkipVerify=true"
    ] : [],

    # Polling configuration
    [
      "--hub.providers.nutanixPrismCentral.pollInterval=${var.nutanix_provider.poll_interval}",
      "--hub.providers.nutanixPrismCentral.pollTimeout=${var.nutanix_provider.poll_timeout}"
    ],

    # Category key for service discovery
    ["--hub.providers.nutanixPrismCentral.serviceNameCategoryKey=TraefikServiceName"],

    # Optional supplementary config file (healthchecks, LB settings, etc.)
    var.nutanix_provider.filename != "" ? [
      "--hub.providers.nutanixPrismCentral.filename=${var.nutanix_provider.filename}"
    ] : []
  ) : []

  # TLS Configuration for EntryPoints (moved from ports.websecure.tls due to Helm schema strictness).
  cli_args_tls = var.cloudflare_dns.enabled || var.dns_traefiker.enabled ? [
    "--entrypoints.websecure.http.tls.certResolver=cf",
    "--entrypoints.websecure.http.tls.domains[0].main=${local.dns_domain}",
    "--entrypoints.websecure.http.tls.domains[0].sans=${join(",", distinct(concat(
      ["*.${local.dns_domain}"],
      var.cloudflare_dns.extra_san_domains,
      var.dns_traefiker.enable_airlines_subdomain ? [
        "*.airlines.${local.dns_domain}",
      ] : []
    )))}"
  ] : []

  additional_arguments = concat(
    local.cli_args_debug,
    local.cli_args_file_provider,
    local.cli_args_http_provider,
    var.custom_arguments,
    local.cli_args_nutanix,
    local.cli_args_tls,
  )
}
