locals {
  loki_exporter                = var.enable_loki ? ["otlphttp/loki"] : []
  tempo_exporter               = var.enable_tempo ? ["otlphttp/tempo"] : []
  newrelic_exporter            = var.enable_new_relic ? ["otlphttp/nri"] : []
  dash0_exporter               = var.enable_dash0 ? ["otlphttp/dash0"] : []
  honeycomb_exporter           = var.enable_honeycomb ? ["otlphttp/honeycomb"] : []
  langsmith_host_filter_active = var.enable_langsmith && length(var.langsmith_host_filter) > 0
  # When a host filter is set, LangSmith rides its own filtered traces pipeline
  # (local.langsmith_pipeline below) instead of the shared traces pipeline.
  langsmith_exporter  = (var.enable_langsmith && !local.langsmith_host_filter_active) ? ["otlphttp/langsmith"] : []
  langfuse_exporter   = var.enable_langfuse ? ["otlphttp/langfuse"] : []
  prometheus_exporter = var.enable_prometheus ? ["prometheus"] : []

  # Trace-derived metrics connectors: each needs BOTH a traces side (they join the
  # trace exporters) and a metrics side to land the generated series in (prometheus).
  # servicegraph -> traces_service_graph_* edge metrics (Grafana's Tempo service map);
  # spanmetrics  -> traces_span_metrics_* RED metrics per service+span (golden signals
  # per compute, straight from the spans — no extra instrumentation).
  servicegraph_enabled   = var.enable_service_graph && var.enable_prometheus
  servicegraph_connector = local.servicegraph_enabled ? ["servicegraph"] : []
  spanmetrics_enabled    = var.enable_span_metrics && var.enable_prometheus
  spanmetrics_connector  = local.spanmetrics_enabled ? ["spanmetrics"] : []

  log_exporters    = concat(local.loki_exporter, local.newrelic_exporter, local.dash0_exporter, local.honeycomb_exporter)
  trace_exporters  = concat(local.tempo_exporter, local.newrelic_exporter, local.dash0_exporter, local.honeycomb_exporter, local.langsmith_exporter, local.langfuse_exporter, local.servicegraph_connector, local.spanmetrics_connector)
  metric_exporters = concat(local.newrelic_exporter, local.dash0_exporter, local.honeycomb_exporter, local.prometheus_exporter)

  logs_pipeline = length(local.log_exporters) > 0 ? concat([
    {
      name  = "config.service.pipelines.logs.receivers[0]"
      value = "otlp"
    },
    {
      name  = "config.service.pipelines.logs.processors[0]"
      value = "batch"
    }
    ], [for exporter in local.log_exporters : {
      name  = "config.service.pipelines.logs.exporters[${index(local.log_exporters, exporter)}]"
      value = exporter
  }]) : []

  # Metrics enter from OTLP pushes, the trace-derived connectors, and (when
  # scrape configs are set) the collector's own Prometheus scraper.
  prom_scrape_enabled = length(var.prometheus_scrape_configs) > 0
  metrics_receivers = concat(
    ["otlp"],
    local.servicegraph_connector,
    local.spanmetrics_connector,
    local.prom_scrape_enabled ? ["prometheus"] : [],
  )

  metrics_pipeline = length(local.metric_exporters) > 0 ? concat(
    [for i, r in local.metrics_receivers : {
      name  = "config.service.pipelines.metrics.receivers[${i}]"
      value = r
      }], [
      {
        name  = "config.service.pipelines.metrics.processors[0]"
        value = "batch"
      }
      ], [for exporter in local.metric_exporters : {
        name  = "config.service.pipelines.metrics.exporters[${index(local.metric_exporters, exporter)}]"
        value = exporter
  }]) : []

  traces_pipeline = length(local.trace_exporters) > 0 ? concat([
    {
      name  = "config.service.pipelines.traces.receivers[0]"
      value = "otlp"
    },
    {
      name  = "config.service.pipelines.traces.processors[0]"
      value = "batch"
    }
    ], [for exporter in local.trace_exporters : {
      name  = "config.service.pipelines.traces.exporters[${index(local.trace_exporters, exporter)}]"
      value = exporter
  }]) : []

  # Dedicated, host-filtered traces pipeline for LangSmith. The tail_sampling
  # processor (defined in the config block) keeps a whole trace only when it
  # matches langsmith_host_filter, so the AI gateway's full trace tree reaches
  # LangSmith while everything else is dropped before export.
  langsmith_pipeline = local.langsmith_host_filter_active ? [
    {
      name  = "config.service.pipelines.traces/langsmith.receivers[0]"
      value = "otlp"
    },
    {
      name  = "config.service.pipelines.traces/langsmith.processors[0]"
      value = "tail_sampling/langsmith"
    },
    {
      name  = "config.service.pipelines.traces/langsmith.processors[1]"
      value = "batch"
    },
    {
      name  = "config.service.pipelines.traces/langsmith.exporters[0]"
      value = "otlphttp/langsmith"
    },
  ] : []

  service_pipelines = concat(local.logs_pipeline, local.metrics_pipeline, local.traces_pipeline, local.langsmith_pipeline)
}

resource "helm_release" "opentelemetry" {
  name       = var.name
  namespace  = var.namespace
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "0.158.1"
  timeout    = 900
  atomic     = true

  values = [
    yamlencode({
      mode = "deployment"
      image = {
        repository = "otel/opentelemetry-collector-contrib"
        tag        = "latest"
      }
      ports = {
        metrics = {
          enabled       = true
          containerPort = var.prometheus_port
          servicePort   = var.prometheus_port
        }
      }
      config = {
        receivers = merge({
          otlp = {
            protocols = {
              http = {
                endpoint = "0.0.0.0:4318"
              }
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
            }
          }
          }, local.prom_scrape_enabled ? {
          # Hub-side pull for exporters that can't push (spoke node_exporters):
          # the hub collector scrapes them over private networking, so every
          # signal still funnels through this one collector.
          prometheus = {
            config = {
              scrape_configs = var.prometheus_scrape_configs
            }
          }
        } : {})
        # Trace-derived metrics: connectors consume the traces pipeline (as exporters)
        # and emit generated series into the metrics pipeline (as receivers).
        # servicegraph -> Grafana's Tempo service map (grafana/k8s sets
        # serviceMap.datasourceUid); spanmetrics -> RED per service+span.
        connectors = merge(
          local.servicegraph_enabled ? {
            servicegraph = {
              latency_histogram_buckets = ["10ms", "50ms", "100ms", "250ms", "1s", "5s"]
              store = {
                ttl       = "10s"
                max_items = 5000
              }
              # NB: virtual_node_peer_attributes is deliberately NOT set. Cloud Run
              # backends can't be paired to the caller's client span — Google's
              # managed frontend re-parents the request, so the whoami server span's
              # parent is a hop we never receive — but turning on peer-attribute
              # virtual nodes to compensate surfaces the Traefik children's cloud-API
              # polling (run.googleapis.com, compute.googleapis.com) as noise nodes
              # and still only labels the backend by its opaque run.app host. The
              # trace view shows the Cloud Run leg correctly regardless.
            }
          } : {},
          local.spanmetrics_enabled ? {
            spanmetrics = {
              histogram = {
                explicit = { buckets = ["10ms", "50ms", "100ms", "250ms", "1s", "5s"] }
              }
              # status_code gives the error dimension; http attrs make the RED
              # panels sliceable by route/method without re-instrumenting.
              dimensions = [
                { name = "http.request.method" },
                { name = "http.response.status_code" },
              ]
              exemplars                       = { enabled = true }
              metrics_flush_interval          = "15s"
              resource_metrics_key_attributes = ["service.name"]
            }
          } : {},
        )
        processors = merge({
          batch = {
            timeout = "5s"
          }
          }, local.langsmith_host_filter_active ? {
          # Trace-level host filter for LangSmith. Tail sampling is required (not a
          # per-span filter): the GenAI/upstream spans carry the provider host
          # (e.g. api.openai.com), not the gateway host, so a per-span filter would
          # strip the AI detail out of the trace. This keeps or drops the whole trace
          # based on whether any span's server.address matches langsmith_host_filter.
          "tail_sampling/langsmith" = {
            decision_wait = "10s"
            policies = [{
              name = "langsmith-host-allowlist"
              type = "string_attribute"
              string_attribute = {
                key                    = "server.address"
                values                 = var.langsmith_host_filter
                enabled_regex_matching = true
              }
            }]
          }
        } : {})
        exporters = merge(
          var.enable_loki ? {
            "otlphttp/loki" = {
              endpoint = var.loki_endpoint
              tls = {
                insecure = true
              }
            }
            } : {}, var.enable_tempo ? {
            "otlphttp/tempo" = {
              endpoint = var.tempo_endpoint
              tls = {
                insecure = true
              }
            }
            } : {}, var.enable_new_relic ? {
            "otlphttp/nri" = {
              endpoint = var.newrelic_endpoint
              headers = {
                api-key = var.newrelic_license_key
              }
            }
            } : {}, var.enable_dash0 ? {
            "otlphttp/dash0" = {
              endpoint = var.dash0_endpoint
              headers = {
                Authorization = "Bearer ${var.dash0_auth_token}"
                Dash0-Dataset = var.dash0_dataset
              }
            }
            } : {}, var.enable_honeycomb ? {
            "otlphttp/honeycomb" = {
              endpoint = var.honeycomb_endpoint
              headers = {
                x-honeycomb-team    = var.honeycomb_api_key
                x-honeycomb-dataset = var.honeycomb_dataset
              }
            }
            } : {}, var.enable_langsmith ? {
            "otlphttp/langsmith" = {
              endpoint    = var.langsmith_endpoint
              compression = "gzip"
              headers = {
                x-api-key         = var.langsmith_api_key
                Langsmith-Project = var.langsmith_project
              }
            }
            } : {}, var.enable_langfuse ? {
            "otlphttp/langfuse" = {
              endpoint    = var.langfuse_endpoint
              compression = "gzip"
              headers = {
                Authorization = "Basic ${base64encode("${var.langfuse_public_key}:${var.langfuse_secret_key}")}"
              }
            }
            } : {}, var.enable_prometheus ? {
            "prometheus" = {
              endpoint = "0.0.0.0:${var.prometheus_port}"
            }
        } : {}, {})
      }
      }
    ),
    yamlencode(var.ingress == true ? {
      ingress = {
        enabled = true
        hosts = [{
          host = "collector.${var.ingress_domain}"
          paths = [{
            path     = "/"
            pathType = "Prefix"
            port     = 4318
          }]
        }]
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

  set = local.service_pipelines
}
