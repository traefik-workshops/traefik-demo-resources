# =============================================================================
# K8s Traefik Deployment
# =============================================================================
# Uses module.config.helm_values as base configuration, merged with K8s-specific
# overrides (redis, knative, gateway, providers, RBAC).
# =============================================================================

locals {
  # Combine shared arguments with K8s-specific ones
  additional_arguments = module.config.cli_arguments

  # K8s-specific volumes for file provider + user-provided additional volumes.
  # NOTE: var.additional_volumes / _mounts are typed `any` (not list(any)) so a
  # mixed-type object (e.g. a CSI volume with a `readOnly` bool) isn't coerced to
  # map(string) — list(any) stringifies the bool, which breaks the spiffe-csi-driver.
  deployment_volumes = concat(
    var.file_provider_config != "" ? [{
      name      = "traefik-dynamic-config"
      configMap = { name = "traefik-dynamic-config" }
    }] : [],
    var.additional_volumes,
  )

  volume_mounts = concat(
    var.file_provider_config != "" ? [{
      name      = "traefik-dynamic-config"
      mountPath = "/etc/traefik/dynamic/"
    }] : [],
    var.additional_volume_mounts,
  )

  # K8s-specific overrides to merge with shared helm_values
  k8s_overrides = {
    # Hub - extend with K8s-specific redis config for API Management
    hub = var.enable_api_gateway || var.enable_api_management ? merge(
      try(module.config.helm_values.hub, {}),
      merge(
        { token = "traefik-hub-license" },
        var.enable_api_management ? {
          apimanagement = { enabled = true }
        } : {}
      ),
      var.enable_api_management ? {
        redis = {
          endpoints = "traefik-redis.${var.namespace}.svc:6379"
          password  = var.redis_password
          database  = "0"
          sentinel  = { enabled = false }
          cluster   = false
        }
      } : {}
    ) : null

    # Deployment configuration
    deployment = {
      kind              = var.deployment_type
      replicas          = module.config.replica_count
      additionalVolumes = local.deployment_volumes
      podAnnotations = var.file_provider_config != "" ? {
        "checksum/fileprovider" = sha256(var.file_provider_config)
      } : {}
    }

    # Service configuration
    #
    # `spec.type`, NOT `kind` and NOT a top-level `type`. Chart 40.x moved the Service type
    # into the free-form `service.spec` passthrough ("Additional entries here will be added
    # to the Service spec"), so `service.kind` — which this module sent for a long time — is
    # an unrecognised key that Helm silently discards, leaving every release on the chart's
    # LoadBalancer default. Verified against 40.3.0: only `--set service.spec.type=ClusterIP`
    # renders `type: ClusterIP`; `service.kind` and `service.type` both still render
    # LoadBalancer.
    #
    # Latent until now because every demo wanted the LoadBalancer default. It surfaced when a
    # SECOND Traefik on a single-node cluster silently became a LoadBalancer too, its klipper
    # DaemonSet could not bind the node's already-taken :80/:443, the Service sat <pending>,
    # and the release failed with nothing but `context deadline exceeded` to go on.
    # externalTrafficPolicy belongs in `spec` for the SAME reason as `type`, and it was
    # missed on the first pass of this fix. At the service level it is an unrecognised key
    # Helm discards, so var.external_traffic_policy was silently a no-op too — verified
    # against 40.3.0: only `--set service.spec.externalTrafficPolicy=Local` renders it.
    #
    # It is not cosmetic. Left on the chart's Cluster default, kube-proxy SNATs every
    # request and Traefik sees the node address instead of the caller's: access logs show a
    # single client for the whole world, and any source-IP middleware (ipAllowList, rate
    # limiting per client) silently matches nothing or everything. That is how it was found
    # — an ipAllowList pinned to the operator's address 403'd the operator.
    service = {
      spec = {
        type                  = var.service_type
        externalTrafficPolicy = var.external_traffic_policy
      }
      annotations = var.service_annotations
    }

    # IngressClass configuration
    ingressClass = {
      enabled        = true
      isDefaultClass = var.ingress_class_is_default
      name           = var.ingress_class_name
    }

    # Default TLSStore via chart values — the chart's tlsstore.yaml renders
    # .Values.tlsStore.<name> verbatim as the TLSStore spec, so this replaces
    # per-demo kubectl_manifest TLSStores. null is stripped below.
    tlsStore = var.default_generated_cert != null ? {
      default = {
        defaultGeneratedCert = {
          resolver = var.default_generated_cert.resolver
          domain   = { main = var.default_generated_cert.domain }
        }
      }
    } : null

    # Environment variables
    env = concat(
      # dns-traefiker path: the cf resolver's DNS-01 token comes from the domain-secret
      # dns-traefiker writes — referenced via secretKeyRef so no token literal lands in
      # helm values/state, and the POD (not the plan) resolves it: no plan-time
      # chicken-and-egg on the secret existing before the first Traefik apply.
      var.dns_traefiker.enabled ? [{ name = "CF_DNS_API_TOKEN", valueFrom = { secretKeyRef = { name = "domain-secret", key = "token" } } }] : [],
      # cloudflare_dns path (no dns-traefiker): the cf resolver's DNS-01 challenge
      # still needs the token — feed it from cloudflare_dns.api_token directly.
      !var.dns_traefiker.enabled && var.cloudflare_dns.enabled && var.cloudflare_dns.api_token != "" ? [{ name = "CF_DNS_API_TOKEN", value = var.cloudflare_dns.api_token }] : [],
      module.config.env_vars_list
    )

    # K8s providers (not in shared)
    providers = merge({
      kubernetesCRD = merge({
        allowCrossNamespace       = true
        allowExternalNameServices = true
        }, length(var.kubernetes_namespaces) > 0 ? {
        namespaces = var.kubernetes_namespaces
      } : {})
      kubernetesIngress = merge({
        allowExternalNameServices = true
        }, length(var.kubernetes_namespaces) > 0 ? {
        namespaces = var.kubernetes_namespaces
      } : {})
      kubernetesGateway = merge({
        enabled             = false
        experimentalChannel = false
        }, length(var.kubernetes_namespaces) > 0 ? {
        namespaces = var.kubernetes_namespaces
      } : {})
      }, var.enable_knative_provider ? {
      knative = {
        enabled = true
      }
    } : {}, var.custom_providers)

    experimental = {
      kubernetesGateway = { enabled = false }
      knative           = var.enable_knative_provider
    }

    # Gateway API listeners (K8s-specific). The chart requires each listener port to be a
    # DECLARED entrypoint CONTAINER port (ports.<name>.port — web=8000, traefik=8080), not
    # the published Service port (80): gateway.yaml fails with "port 80 is not declared in
    # ports" otherwise. The Service still publishes web on :80 (exposedPort).
    gateway = {
      listeners = {
        web = {
          port            = 8000
          protocol        = "HTTP"
          namespacePolicy = { from = "All" }
        }
        traefik = {
          port            = 8080
          protocol        = "HTTP"
          namespacePolicy = { from = "All" }
        }
      }
    }

    # Pod security (K8s-specific)
    podSecurityContext = {
      fsGroup             = 65532
      fsGroupChangePolicy = "OnRootMismatch"
    }

    # Resources and tolerations (K8s-specific)
    resources   = var.resources
    tolerations = var.tolerations

    # Additional arguments and volumes (K8s-specific)
    additionalArguments    = local.additional_arguments
    additionalVolumeMounts = local.volume_mounts
    extraObjects           = var.custom_objects
  }
}

# K8s Secrets
resource "kubernetes_secret_v1" "traefik_hub_license" {
  count = var.enable_api_gateway || var.enable_api_management ? 1 : 0

  metadata {
    name      = "traefik-hub-license"
    namespace = var.namespace
  }

  type = "Opaque"
  data = {
    token = var.traefik_hub_token
  }
}

# Restored ACME store — see var.acme_store_restore for why this exists at all.
#
# These have to be in place BEFORE the gateway starts, not after: Hub's KubernetesStore
# reads through an informer whose initial list happens at startup, and Traefik decides
# whether to order during that same pass. A Secret that lands afterwards is read, but only
# once the order it was meant to prevent has already gone out.
#
# Ownership is left alone on purpose. Hub stamps each certificate Secret with an
# ownerReference to the ACME account Secret, carrying that account's UID — a UID that
# belonged to a cluster which no longer exists. Replaying it would point the garbage
# collector at an owner it cannot find and the certificate would be deleted out from under
# the gateway. Restoring without ownerReferences is safe: Hub re-establishes them the first
# time it saves.
resource "kubernetes_secret_v1" "acme_store_restore" {
  for_each = { for s in var.acme_store_restore : s.name => s }

  metadata {
    name      = each.value.name
    namespace = var.namespace
    labels    = each.value.labels
  }

  type = each.value.type
  # base64 in, base64 out — `data` would double-encode what kubectl already encoded.
  binary_data = each.value.data

  # Hub owns these once it is running: it renews the certificate in place and prunes
  # entries it no longer wants. Terraform re-asserting the checkpoint on a later apply
  # would roll a renewed certificate back to the one this run started with.
  lifecycle {
    ignore_changes = [binary_data, metadata[0].labels, metadata[0].annotations]
  }
}

# File provider ConfigMap
resource "kubernetes_config_map_v1" "traefik_dynamic_config" {
  count = var.file_provider_config != "" ? 1 : 0

  metadata {
    name      = "traefik-dynamic-config"
    namespace = var.namespace
  }

  data = {
    "dynamic.yaml" = var.file_provider_config
  }
}

# Helm release - merge shared helm_values with K8s overrides
resource "helm_release" "traefik" {
  name             = var.name
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  namespace        = var.namespace
  create_namespace = true
  atomic           = true
  wait             = true
  timeout          = 900

  values = [
    # Base values from shared module
    yamlencode(module.config.helm_values),
    # K8s-specific overrides (strip null values)
    yamlencode({ for k, v in local.k8s_overrides : k => v if v != null }),
    # User-provided extra values
    yamlencode(var.extra_values)
  ]

  depends_on = [
    kubernetes_secret_v1.traefik_hub_license,
    kubernetes_secret_v1.acme_store_restore,
    kubernetes_config_map_v1.traefik_dynamic_config,
    null_resource.traefik_crds,
    helm_release.dns_traefiker
  ]
}

resource "helm_release" "dns_traefiker" {
  count = var.dns_traefiker.enabled ? 1 : 0

  name      = "dns-traefiker"
  namespace = var.namespace

  chart = var.dns_traefiker.chart
  # Pin only when the caller asks: local chart paths carry no version, and an OCI chart
  # without one installs whatever "latest" is that day — fine for a lab, wrong for a
  # workshop repo that must be reproducible at a tagged ref.
  version = var.dns_traefiker.chart_version != "" ? var.dns_traefiker.chart_version : null

  values = [
    yamlencode({
      uniqueDomain            = var.dns_traefiker.unique_domain
      domain                  = var.dns_traefiker.domain
      enableAirlinesSubdomain = var.dns_traefiker.enable_airlines_subdomain
      ipOverride              = var.dns_traefiker.ip_override
      proxied                 = var.dns_traefiker.proxied
      traefikServiceName      = "traefik"
      traefikServiceNamespace = var.namespace
    })
  ]
}

data "kubernetes_secret_v1" "dns_domain" {
  count = var.dns_traefiker.enabled ? 1 : 0

  metadata {
    name      = "domain-secret"
    namespace = var.namespace
  }

  depends_on = [helm_release.dns_traefiker]
}

# Redis for API Management — the distributed store behind plan rate limits and quotas
# ("RateLimit and Quota can be used only if the redis server is configured", Hub's own
# plan middleware). NOT the certificate store: distributed ACME is configured with
# `storage.kubernetes = true` in ../shared/helm_values.tf, and Hub accepts no Redis
# ACME storage at all — so persistence off costs counters, never a re-issued cert.
module "redis" {
  source = "../../tools/redis/k8s"
  count  = var.enable_api_management ? 1 : 0

  name          = "traefik-redis"
  namespace     = var.namespace
  password      = var.redis_password
  replica_count = var.replica_count
  persistence   = var.redis_persistence
}
