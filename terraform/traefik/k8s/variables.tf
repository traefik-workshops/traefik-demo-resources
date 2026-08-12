# =============================================================================
# K8s-specific Variables
# =============================================================================
# Shared Traefik variables are defined in shared.tf.
# This file contains only K8s platform-specific variables.
# =============================================================================

variable "name" {
  description = "The name of the traefik release"
  type        = string
  default     = "traefik"
}

variable "namespace" {
  description = "Namespace for the Traefik Hub deployment"
  type        = string
}

variable "deployment_type" {
  description = "Traefik deployment type"
  type        = string
  default     = "Deployment"
}

variable "replica_count" {
  description = "Number of replicas for the Traefik Hub deployment"
  type        = number
  default     = 1
}

variable "service_type" {
  description = "Traefik service type"
  type        = string
  default     = "LoadBalancer"
}

variable "resources" {
  description = "Resources for the Traefik deployment. Set to null or leave empty strings to use chart defaults."
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = null
}

variable "tolerations" {
  description = "Tolerations for the Traefik deployment"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}

variable "redis_password" {
  description = "Redis password for API Management"
  type        = string
  default     = "topsecretpassword"
  sensitive   = true
}

variable "redis_persistence" {
  description = "Back the API Management Redis with a PersistentVolumeClaim (8Gi RWO) instead of emptyDir. Default FALSE — the claim is a real cloud disk that outlives `terraform destroy`, and this Redis holds only plan rate-limit/quota counters, never ACME certificates. See the note in ../../tools/redis/k8s/main.tf."
  type        = bool
  default     = false
}

variable "skip_crds" {
  description = "Skip CRD installation (for NKP/Kommander clusters with pre-installed CRDs)"
  type        = bool
  default     = false
}

variable "kubeconfig" {
  description = "Path to a kubeconfig the CRD install (local-exec kubectl) should use. Empty = ambient kubeconfig / current context. Set this when the cluster is created in the same terraform run, so kubectl has no current context yet (e.g. demos that build a k3d cluster in-config)."
  type        = string
  default     = ""
}

variable "kubeconfig_context" {
  description = "kubectl/helm context for the CRD install (local-exec). Set it so the apply targets a named context instead of whatever the machine-global current-context happens to be at that instant (a parallel standup or a mid-apply context switch would otherwise install CRDs into the WRONG cluster). Combines with `kubeconfig` (context within that file). Empty = ambient kubeconfig / current context — today's behavior."
  type        = string
  default     = ""
}

variable "skip_gateway_api_crds" {
  description = "Skip Gateway API CRD installation"
  type        = bool
  default     = false
}

variable "enable_knative_provider" {
  description = "Enable Knative provider"
  type        = bool
  default     = false
}

variable "custom_providers" {
  type        = any
  description = "Custom providers to use for the deployment"
  default     = {}
}

variable "custom_objects" {
  type        = list(object({}))
  description = "Extra Kubernetes objects to deploy"
  default     = []
}

variable "extra_values" {
  type        = any
  description = "Extra Helm values to merge"
  default     = {}
}

variable "default_generated_cert" {
  description = "Default TLSStore generated-certificate config, rendered as chart values tlsStore.default.defaultGeneratedCert.{resolver,domain.main} (the chart emits the TLSStore CRD — no hand-rolled manifest needed). null = no default TLSStore. `resolver` must name a configured certificates resolver (e.g. \"cf\"); `domain` is the cert's main domain (e.g. \"*.example.com\")."
  type = object({
    resolver = string
    domain   = string
  })
  default = null
}

variable "kubernetes_namespaces" {
  description = "List of namespaces to watch for Kubernetes providers (Ingress, Gateway, CRD)"
  type        = list(string)
  default     = []
}

variable "service_annotations" {
  description = "Extra annotations for the Traefik service"
  type        = map(string)
  default     = {}
}

variable "ingress_class_name" {
  description = "The name of the ingress class"
  type        = string
  default     = "traefik"
}

variable "ingress_class_is_default" {
  description = "Whether this ingress class is the default"
  type        = bool
  default     = true
}

variable "external_traffic_policy" {
  description = "The external traffic policy for the Traefik service"
  type        = string
  default     = "Cluster"
}

# =============================================================================
# Shared Variable Declarations
# =============================================================================

# Feature Flags
variable "enable_api_gateway" {
  description = "Enable Traefik Hub API Gateway features"
  type        = bool
  default     = false
}

variable "enable_ai_gateway" {
  description = "Enable Traefik Hub AI Gateway features"
  type        = bool
  default     = false
}

variable "enable_mcp_gateway" {
  description = "Enable MCP Gateway (Claude, etc.)"
  type        = bool
  default     = false
}

variable "enable_api_management" {
  description = "Enable Traefik Hub API Management features"
  type        = bool
  default     = false
}

variable "enable_offline_mode" {
  description = "Enable Traefik Hub Offline mode"
  type        = bool
  default     = false
}

variable "enable_preview_mode" {
  description = "Enable Traefik Hub Preview features"
  type        = bool
  default     = false
}

variable "enable_debug" {
  description = "Enable Traefik debug mode (pprof)"
  type        = bool
  default     = false
}

# Versions & Images
variable "traefik_chart_version" {
  description = "Traefik Helm chart version (latest stable). Must render the partial metrics.otlp block this module sets: chart 38.x nil-pointers on .Values.metrics.otlp.resourceAttributes when that block is set without it; 40.x renders it."
  type        = string
  default     = "40.3.0"
}

variable "traefik_tag" {
  description = "Traefik OSS version tag"
  type        = string
  default     = "v3.7.4"
}

variable "traefik_hub_tag" {
  description = "Traefik Hub image tag for ghcr.io/traefik/traefik-hub (latest stable), paired with the default chart version above."
  type        = string
  default     = "v3.20.4"
}

variable "traefik_hub_preview_tag" {
  description = "Traefik Hub preview version tag"
  type        = string
  default     = ""
}

variable "custom_image_registry" {
  description = "Custom image registry"
  type        = string
  default     = ""
}

variable "custom_image_repository" {
  description = "Custom image repository"
  type        = string
  default     = ""
}

variable "custom_image_tag" {
  description = "Custom image tag"
  type        = string
  default     = ""
}

# Observability
variable "log_level" {
  description = "Log level (DEBUG, INFO, WARN, ERROR)"
  type        = string
  default     = "INFO"
}

variable "otlp_address" {
  description = "OTLP collector endpoint"
  type        = string
  default     = ""
}

variable "otlp_service_name" {
  description = "Service name for telemetry"
  type        = string
  default     = "traefik"
}

variable "enable_otlp_access_logs" {
  description = "Enable OTLP access logs"
  type        = bool
  default     = false
}

variable "enable_otlp_application_logs" {
  description = "Enable OTLP application logs"
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Enable Traefik access logs"
  type        = bool
  default     = true
}

variable "enable_otlp_metrics" {
  description = "Enable OTLP metrics"
  type        = bool
  default     = false
}

variable "enable_otlp_traces" {
  description = "Enable OTLP traces"
  type        = bool
  default     = false
}

variable "enable_prometheus" {
  description = "Enable Prometheus metrics"
  type        = bool
  default     = false
}

# Plugins & Extensions
variable "custom_plugins" {
  description = "Custom plugins to use for the deployment"
  type = map(object({
    moduleName = string
    version    = string
  }))
  default = {}
}

variable "custom_ports" {
  description = "Custom ports configuration"
  type        = any
  default     = {}
}

variable "custom_arguments" {
  description = "Additional CLI arguments for Traefik"
  type        = list(string)
  default     = []
}

variable "custom_envs" {
  description = "Custom environment variables"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "additional_volumes" {
  description = "Additional volumes to mount in the Traefik pod"
  # `any`, not list(any): list(any) coerces mixed-type objects (e.g. a CSI volume
  # carrying a readOnly bool) to map(string), stringifying the bool.
  type    = any
  default = []
}

variable "additional_volume_mounts" {
  description = "Additional volume mounts for the Traefik container"
  # `any`, not list(any) — see additional_volumes above (readOnly bool coercion).
  type    = any
  default = []
}

variable "file_provider_config" {
  description = "YAML configuration for Traefik file provider"
  type        = string
  default     = ""
}

variable "file_provider_path" {
  description = "Path where the file provider config is mounted"
  type        = string
  default     = "/etc/traefik/dynamic"
}

# Licensing & DNS
variable "traefik_hub_token" {
  description = "Traefik Hub license token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_dns" {
  description = "Cloudflare DNS configuration for certificate resolver"
  type = object({
    enabled           = optional(bool, false)
    domain            = optional(string, "")
    api_token         = optional(string, "")
    extra_san_domains = optional(list(string), [])
  })
  default = {
    enabled           = false
    domain            = ""
    api_token         = ""
    extra_san_domains = []
  }
  sensitive = true
}

variable "is_staging_letsencrypt" {
  description = "Use Let's Encrypt staging environment"
  type        = bool
  default     = false
}

variable "use_distributed_acme" {
  description = "Use distributedAcme instead of acme (stores certs in K8s secrets instead of acme.json file)"
  type        = bool
  default     = true
}

# Handing the previous cluster's ACME store back is what turns a rebuild into a RENEWAL
# rather than a fresh order.
#
# `use_distributed_acme` puts Hub's ACME store in Kubernetes Secrets, and those Secrets die
# with the cluster. Every apply therefore starts from an EMPTY store and places a brand new
# order for the same names. Let's Encrypt counts that two ways and both bite:
#
#   * 5 certificates per 168h for one EXACT identifier set. aws-unified-ingress hit it on
#     2026-08-11 and was un-runnable for fifteen hours — and it lands as every act curling
#     000 against CN=TRAEFIK DEFAULT CERT, not as anything that reads like a quota.
#   * 50 certificates per REGISTERED DOMAIN per week — traefik.ai, shared by the whole
#     fleet and by anything else issued under it. A repeat order for a set that was already
#     issued counts as a RENEWAL and is exempt from this one; a name nobody has ordered
#     before is not. Minting a fresh subdomain per run dodges the first ceiling by spending
#     the second.
#
# Seeding the store in front of the Helm release takes ACME out of the standup entirely:
# Traefik finds a certificate that is still valid and only renews inside the last 30 days
# of its 90-day life (getCertificateRenewDurations, traefik/pkg/provider/acme). Nothing is
# ordered, nothing is counted, and the cold DNS-01 issuance every validation currently pays
# stops eating the warmup budget.
#
# Deliberately a CACHE, never a dependency. Empty — the default — is exactly today's
# behaviour, a cold issuance. A stale or mismatched entry is not a trap either: Traefik
# falls through to ordering, and Hub deletes what it no longer wants on its next save
# (SaveCertificates prunes anything outside the wanted set). A demo handed to an operator
# who has no checkpoint still stands up, just slower — which is the point, because a
# standup that silently needs state a previous operator made is worse than a slow one.
#
# The shape is "the Secrets as kubectl emits them" rather than a friendlier cert/key pair
# because the store is Hub's, not ours: names, labels and data keys are all computed in
# hub/pkg/hub/acme/kubernetes_store.go, and a checkpoint that round-trips verbatim cannot
# drift from them. Matching the name matters only for tidiness — the store lists by LABEL,
# so a restored Secret is read even under a foreign name, and Hub renames it on its first
# save. Take a checkpoint off a healthy cluster with:
#
#   kubectl -n traefik get secret -l app.kubernetes.io/managed-by=traefik-hub \
#     -o json | jq '[.items[]
#       | select(.metadata.labels["app.kubernetes.io/component"]
#                | test("^acme-(account|certificate)$"))
#       | {name: .metadata.name, type: .type, labels: .metadata.labels, data: .data}]'
#
# `data` stays base64 all the way through, which is why it lands in `binary_data` below.
#
# NOT marked `sensitive`: Terraform rejects a sensitive value in `for_each`, and the
# material is redacted regardless — the kubernetes provider marks `binary_data` sensitive
# itself. It reaches the state file either way, next to the Hub token above.
variable "acme_store_restore" {
  description = "ACME store checkpoint taken off an earlier cluster, restored before Traefik starts so a rebuild serves the certificate it already holds instead of ordering a new one. Each element is one Hub-managed Secret verbatim — name, type, labels, and base64 data — as emitted by `kubectl get secret -l app.kubernetes.io/managed-by=traefik-hub -o json`. Empty (the default) is a normal cold ACME issuance."
  type = list(object({
    name   = string
    type   = optional(string, "Opaque")
    labels = map(string)
    data   = map(string)
  }))
  default = []
}

# Dashboard
variable "dashboard_entrypoints" {
  description = "Dashboard entry points"
  type        = list(string)
  default     = ["traefik"]
}

variable "dashboard_match_rule" {
  description = "Match rule for the Traefik dashboard router"
  type        = string
  default     = ""
}

variable "enable_dashboard" {
  description = "Enable Traefik dashboard"
  type        = bool
  default     = true
}

variable "dashboard_insecure" {
  description = "Enable insecure dashboard access (no auth)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------
variable "multicluster_provider" {
  description = "Traefik Hub multicluster provider configuration"
  type = object({
    enabled      = optional(bool, false)
    pollInterval = optional(number, null)
    pollTimeout  = optional(number, null)
    children     = optional(any, {})
  })
  default = {
    enabled = false
  }
}

variable "nutanix_provider" {
  description = "Nutanix Prism Central provider configuration for VM discovery"
  type = object({
    enabled              = optional(bool, false)
    endpoint             = optional(string, "")
    username             = optional(string, "")
    password             = optional(string, "")
    api_key              = optional(string, "")
    insecure_skip_verify = optional(bool, false)
    poll_interval        = optional(string, "30s")
    poll_timeout         = optional(string, "5s")
  })
  default = {
    enabled = false
  }
  sensitive = true
}

variable "dns_traefiker" {
  description = "DNS Traefiker configuration for automatic domain registration. `chart` accepts a local path OR a fully-qualified OCI reference (oci://ghcr.io/traefik-workshops/dns-traefiker); OCI installs resolve the LATEST tag unless chart_version pins one, so remote consumers should always set chart_version."
  type = object({
    enabled                   = optional(bool, false)
    chart                     = optional(string, "")
    chart_version             = optional(string, "")
    unique_domain             = optional(bool, false)
    domain                    = optional(string, "")
    enable_airlines_subdomain = optional(bool, false)
    ip_override               = optional(string, "")
    proxied                   = optional(bool, false)
  })
  default = {
    enabled = false
  }
}
