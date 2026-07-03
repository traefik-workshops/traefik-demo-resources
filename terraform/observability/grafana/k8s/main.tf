locals {
  prometheus_url = var.prometheus.url.override != "" ? var.prometheus.url.override : "http://${var.prometheus.url.service}${var.prometheus.url.namespace != "" ? ".${var.prometheus.url.namespace}.svc" : ""}:${var.prometheus.url.port}"
  tempo_url      = var.tempo.url.override != "" ? var.tempo.url.override : "http://${var.tempo.url.service}${var.tempo.url.namespace != "" ? ".${var.tempo.url.namespace}.svc" : ""}:${var.tempo.url.port}"
  loki_url       = var.loki.url.override != "" ? var.loki.url.override : "http://${var.loki.url.service}${var.loki.url.namespace != "" ? ".${var.loki.url.namespace}.svc" : ""}:${var.loki.url.port}"

  # Fixed uids so datasources can reference each other (Tempo's service graph +
  # traces->logs links need the target datasource's uid at provisioning time).
  datasources = concat(
    var.prometheus.enabled ? [{
      name      = "Prometheus"
      uid       = "prometheus"
      type      = "prometheus"
      url       = local.prometheus_url
      access    = "proxy"
      isDefault = true
    }] : [],
    var.tempo.enabled ? [{
      name      = "Tempo"
      uid       = "tempo"
      type      = "tempo"
      url       = local.tempo_url
      access    = "proxy"
      isDefault = !var.prometheus.enabled
      # Service graph: the map is drawn from traces_service_graph_* metrics that the
      # OTel collector's servicegraph connector writes to Prometheus (the otel module
      # enables it by default) — serviceMap points Tempo at that Prometheus datasource.
      jsonData = merge(
        { nodeGraph = { enabled = true } },
        var.prometheus.enabled ? { serviceMap = { datasourceUid = "prometheus" } } : {},
        var.loki.enabled ? {
          tracesToLogsV2 = {
            datasourceUid      = "loki"
            spanStartTimeShift = "-5m"
            spanEndTimeShift   = "5m"
            filterByTraceID    = true
          }
          lokiSearch = { datasourceUid = "loki" }
        } : {},
      )
    }] : [],
    var.loki.enabled ? [merge({
      name      = "Loki"
      uid       = "loki"
      type      = "loki"
      url       = local.loki_url
      access    = "proxy"
      isDefault = !var.prometheus.enabled && !var.tempo.enabled
      },
      # Logs -> traces (the reverse of Tempo's tracesToLogsV2): every OTLP-ingested
      # log line carries its trace id as structured metadata (`trace_id`) — surface
      # it as a Tempo deep link so a log line jumps straight to its trace.
      var.tempo.enabled ? {
        jsonData = {
          derivedFields = [{
            name            = "TraceID"
            matcherType     = "label"
            matcherRegex    = "trace_id"
            datasourceUid   = "tempo"
            url             = "$${__value.raw}"
            urlDisplayLabel = "View trace"
          }]
        }
      } : {},
  )] : [])

  aigateway_dashboard = "aigateway-dashboards"
  aigateway_path      = "/dashboards/hub/aigateway"

  dashboard_providers = concat(
    var.dashboards.aigateway ? [{
      name                  = local.aigateway_dashboard
      orgId                 = "1"
      type                  = "file"
      disableDeletion       = false
      editable              = true
      updateIntervalSeconds = 10
      options = {
        path = local.aigateway_path
      }
    }] : [],
    [for name, json in var.extra_dashboards : {
      name                  = "custom-${name}"
      orgId                 = "1"
      type                  = "file"
      disableDeletion       = false
      editable              = true
      updateIntervalSeconds = 10
      options = {
        path = "/dashboards/custom/${name}"
      }
    }]
  )

  configmap_mounts = concat(
    var.dashboards.aigateway ? [{
      name      = local.aigateway_dashboard
      mountPath = "${local.aigateway_path}/dashboard.json"
      subPath   = "dashboard.json"
      configMap = local.aigateway_dashboard
      readOnly  = true
    }] : [],
    [for name, json in var.extra_dashboards : {
      name      = "custom-${name}"
      mountPath = "/dashboards/custom/${name}/dashboard.json"
      subPath   = "dashboard.json"
      configMap = "custom-dashboard-${name}"
      readOnly  = true
    }]
  )
}

resource "helm_release" "grafana" {
  name      = var.name
  namespace = var.namespace
  # The grafana chart moved homes: grafana/helm-charts froze it as deprecated
  # at 10.5.15 (2026-01-30); the maintained line continues in
  # grafana-community/helm-charts (12.x). Same values schema — 11.0.0 only
  # raised the k8s floor to 1.25; 12.0.0 defaults to Grafana 13 and auto-wires
  # an image-renderer auth token. Rendered Service/Ingress/ConfigMap diff clean.
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "grafana"
  version    = "12.4.4"
  timeout    = 900
  atomic     = true

  values = [
    yamlencode({
      "grafana.ini" = {
        "auth.anonymous" = {
          enabled  = true
          org_name = "Main Org."
          org_role = "Admin"
        }
        auth = {
          disable_login_form = true
        }
      }
      datasources = {
        "datasources.yaml" = {
          apiVersion  = 1
          datasources = local.datasources
        }
      }
      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1
          providers  = local.dashboard_providers
        }
      }
      extraConfigmapMounts = local.configmap_mounts
      tolerations          = var.tolerations
    }),
    var.image_renderer ? yamlencode({
      imageRenderer = {
        enabled = true
      }
      "grafana.ini" = {
        rendering = {
          server_url   = "http://localhost:8081/render"
          callback_url = "http://localhost:3000/"
        }
      }
    }) : yamlencode({}),
    yamlencode(var.extra_values),
    yamlencode(var.ingress == true ? {
      ingress = {
        enabled = true
        hosts   = ["grafana.${var.ingress_domain}"]
        annotations = merge(
          { "traefik.ingress.kubernetes.io/router.entrypoints" = var.ingress_entrypoint },
          var.ingress_observability ? {} : {
            "traefik.ingress.kubernetes.io/router.observability.accesslogs" = "false"
            "traefik.ingress.kubernetes.io/router.observability.metrics"    = "false"
            "traefik.ingress.kubernetes.io/router.observability.tracing"    = "false"
          },
          var.ingress_annotations,
        )
      }
    } : {})
  ]
}

module "aigateway_dashboard" {
  source = "./dashboards/aigateway"

  name      = local.aigateway_dashboard
  namespace = var.namespace

  count = var.dashboards.aigateway ? 1 : 0
}

resource "kubernetes_config_map_v1" "extra_dashboards" {
  for_each = var.extra_dashboards

  metadata {
    name      = "custom-dashboard-${each.key}"
    namespace = var.namespace
  }

  data = {
    "dashboard.json" = each.value
  }
}
