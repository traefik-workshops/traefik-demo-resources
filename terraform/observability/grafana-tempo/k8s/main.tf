resource "helm_release" "tempo" {
  name       = var.name
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.23.3"
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
