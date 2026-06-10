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
    }),
    yamlencode(var.extra_values)
  ]
}
