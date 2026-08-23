# observability/grafana-stack/k8s

Deploys a full Grafana + Prometheus stack (kube-prometheus-stack) with optional Traefik ingress and demo dashboards.

## Example usage

```hcl
module "grafana_stack" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/observability/grafana-stack/k8s?ref=v7.0.0"

  namespace  = "observability"
  dashboards = { aigateway = true, mcpgateway = false, apim = false }
}
```

## Prerequisites

- A working Kubernetes cluster with `helm` and `kubernetes` providers configured.
- Traefik installed in-cluster if `ingress = true`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_grafana"></a> [grafana](#module\_grafana) | ../../grafana/k8s | n/a |
| <a name="module_observability_grafana_loki"></a> [observability\_grafana\_loki](#module\_observability\_grafana\_loki) | ../../grafana-loki/k8s | n/a |
| <a name="module_observability_grafana_tempo"></a> [observability\_grafana\_tempo](#module\_observability\_grafana\_tempo) | ../../grafana-tempo/k8s | n/a |
| <a name="module_observability_prometheus"></a> [observability\_prometheus](#module\_observability\_prometheus) | ../../prometheus/k8s | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dashboards"></a> [dashboards](#input\_dashboards) | Bundled Traefik Hub dashboards to install via the wrapped grafana module. Toggle each topic on/off independently — AI Gateway, MCP Gateway, API Management, and Unified Ingress dashboards each pull from their own metrics source. `unified_ingress` defaults on so existing call sites light it up without changes. | <pre>object({<br/>    aigateway       = bool<br/>    mcpgateway      = bool<br/>    apim            = bool<br/>    unified_ingress = optional(bool, true)<br/>  })</pre> | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the Grafana deployment | `string` | n/a | yes |
| <a name="input_extra_dashboards"></a> [extra\_dashboards](#input\_extra\_dashboards) | A map of dashboard names to their JSON content. | `map(string)` | `{}` | no |
| <a name="input_grafana_extra_values"></a> [grafana\_extra\_values](#input\_grafana\_extra\_values) | Extra values to pass to the Grafana deployment. | `any` | `{}` | no |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | Enable Ingress for the Grafana deployment. | `bool` | `false` | no |
| <a name="input_ingress_annotations"></a> [ingress\_annotations](#input\_ingress\_annotations) | Additional metadata annotations merged onto each child module's Ingress. Useful for custom router options beyond the three observability toggles. | `map(string)` | `{}` | no |
| <a name="input_ingress_domain"></a> [ingress\_domain](#input\_ingress\_domain) | The domain for the ingress, default is `cloud` | `string` | `"cloud"` | no |
| <a name="input_ingress_entrypoint"></a> [ingress\_entrypoint](#input\_ingress\_entrypoint) | The entrypoint to use for the ingress, default is `traefik` | `string` | `"traefik"` | no |
| <a name="input_ingress_observability"></a> [ingress\_observability](#input\_ingress\_observability) | Emit Traefik observability signals (access logs, metrics, traces) for the stack's Prometheus and Grafana ingress routers. Set to false to add the three `traefik.ingress.kubernetes.io/router.observability.*: "false"` annotations on each child module. Same switch shape as other observability/k8s modules. | `bool` | `true` | no |
| <a name="input_loki_extra_values"></a> [loki\_extra\_values](#input\_loki\_extra\_values) | Extra values to pass to the Loki deployment. | `any` | `{}` | no |
| <a name="input_loki_persistence"></a> [loki\_persistence](#input\_loki\_persistence) | Back Loki's single-binary store and its bundled MinIO with PersistentVolumeClaims instead of emptyDir. Default FALSE — Loki is the only chart in this stack that asks for storage, and each PVC becomes a real cloud disk that `terraform destroy` leaves behind (the CSI reclaim is async and loses the race with the cluster teardown). See the note in ../../grafana-loki/k8s/main.tf. | `bool` | `false` | no |
| <a name="input_metrics_host"></a> [metrics\_host](#input\_metrics\_host) | Host of metrics endpoint | `string` | `""` | no |
| <a name="input_metrics_port"></a> [metrics\_port](#input\_metrics\_port) | Port of metrics endpoint | `number` | `8889` | no |
| <a name="input_prometheus_extra_values"></a> [prometheus\_extra\_values](#input\_prometheus\_extra\_values) | Extra values to pass to the Prometheus deployment. | `any` | `{}` | no |
| <a name="input_prometheus_url_override"></a> [prometheus\_url\_override](#input\_prometheus\_url\_override) | If non-empty, Grafana's Prometheus datasource URL is set to this value instead of the default kube-prometheus-stack service. Useful when you route queries through a Prom-compatible backend like VictoriaMetrics vmselect. | `string` | `""` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for the Grafana deployment. | <pre>list(object({<br/>    key      = string<br/>    operator = string<br/>    value    = string<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
