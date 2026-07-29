resource "helm_release" "tempo" {
  name      = var.name
  namespace = var.namespace
  # The single-binary tempo chart moved homes: grafana/helm-charts froze it as
  # deprecated at 1.24.4 (2026-01-30); the maintained line continues in
  # grafana-community/helm-charts (2.x). Same chart, same values schema — the
  # 2.0.0 major only raised the k8s floor to 1.25 and dropped pre-v1 Ingress.
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "tempo"
  version    = "2.2.1"
  timeout    = 900
  atomic     = true

  values = [
    yamlencode({
      tempo = {
        reportingEnabled = false
        # Pin the Tempo image. The chart default `tempo.tag: ""` resolved to an older
        # 2.9.x image on a fresh cluster (CrashLoopBackOff); pin the chart's current
        # appVersion. (True-latest Tempo is 3.x, but that needs a chart bump — the
        # 2.2.1 config template targets the 2.10 line.)
        tag = "2.10.6"
        # Metrics generator + the local-blocks processor are required for TraceQL
        # metrics — the `{...} | rate() by(...)` queries Grafana's Traces Drilldown
        # runs. Without a running generator the generator ring is empty and the
        # drilldown 500s ("error finding generators in Querier.queryRangeRecent:
        # empty ring"). local-blocks serves TraceQL metrics over recent traces
        # (the queryRangeRecent path); enabling it registers the generator in the
        # ring. The single-binary chart runs the generator in-process (-target=all).
        metricsGenerator = {
          enabled = true
        }
        overrides = {
          defaults = {
            metrics_generator = {
              processors = ["local-blocks"]
            }
          }
        }
      }
      tolerations = var.tolerations
      # Override the chart's whole `config` (top-level key — NOT under `tempo`). The
      # chart default builds distributor.receivers from `{{ toYaml .Values.tempo.receivers }}`,
      # whose default map includes `opencensus` — a receiver the 2.10.x binary DROPPED
      # (it hard-fails: "'receivers' unknown type: opencensus" and CrashLoopBackOffs).
      # Helm can't strip a chart-default key by merge (null doesn't delete it), and the
      # chart's _ports.tpl dereferences receivers.jaeger.protocols so jaeger can't be
      # nulled either — so we render the config and pin receivers to otlp only (the OTel
      # collector forwards traces here over OTLP). Faithful to the chart's 2.2.1 default
      # otherwise: every other block still reads `.Values.tempo.*` via `tpl`, so the
      # metricsGenerator/overrides above and the chart's storage/server/ingester defaults
      # all still apply. Re-check this against the chart's `config` on a Tempo chart bump.
      config = <<-EOT
      stream_over_http_enabled: {{ .Values.tempo.streamOverHttpEnabled }}
      memberlist:
        cluster_label: "{{ .Release.Name }}.{{ .Release.Namespace }}"
      multitenancy_enabled: {{ .Values.tempo.multitenancyEnabled }}
      usage_report:
        reporting_enabled: {{ .Values.tempo.reportingEnabled }}
      compactor:
        compaction:
          block_retention: {{ .Values.tempo.retention }}
      distributor:
        receivers:
          otlp:
            protocols:
              grpc:
                endpoint: 0.0.0.0:4317
              http:
                endpoint: 0.0.0.0:4318
      ingester:
        {{- toYaml .Values.tempo.ingester | nindent 6 }}
      server:
        {{- toYaml .Values.tempo.server | nindent 6 }}
      storage:
        {{- toYaml .Values.tempo.storage | nindent 6 }}
      querier:
        {{- toYaml .Values.tempo.querier | nindent 6 }}
      query_frontend:
        {{- toYaml .Values.tempo.queryFrontend | nindent 6 }}
      overrides:
        {{- toYaml .Values.tempo.overrides | nindent 6 }}
        {{- if .Values.tempo.metricsGenerator.enabled }}
      metrics_generator:
        {{- if .Values.tempo.metricsGenerator.processor }}
        processor:
          {{- toYaml .Values.tempo.metricsGenerator.processor | nindent 8 }}
        {{- end }}
        {{- if .Values.tempo.metricsGenerator.registry }}
        registry:
          {{- toYaml .Values.tempo.metricsGenerator.registry | nindent 8 }}
        {{- end }}
        storage:
          path: {{ .Values.tempo.metricsGenerator.storage.path | quote }}
          {{- if .Values.tempo.metricsGenerator.storage.remote_write }}
          remote_write:
            {{- toYaml .Values.tempo.metricsGenerator.storage.remote_write | nindent 10 }}
          {{- else }}
          remote_write:
            - url: {{ .Values.tempo.metricsGenerator.remoteWriteUrl }}
          {{- end }}
        traces_storage:
          path: {{ .Values.tempo.metricsGenerator.traces_storage.path | quote }}
        {{- end }}
      EOT
    }),
    yamlencode(var.extra_values)
  ]
}
