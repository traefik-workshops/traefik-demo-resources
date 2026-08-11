# tools/k6-operator/k8s/loadgen/traefik-hub

Renders a k6 `TestRun` that drives steady, broad traffic across the `traefik-hub` demo edge
so the Grafana dashboards have something to show. Sibling to [`aigateway`](../aigateway/), but
general-purpose: it exercises the whole demo surface (public edge routes, the managed API per
consumer, WAF attacks, and optionally the AI gateway) rather than only AI chat.

The weighted mix per iteration: ~60% public edge GETs (lb / whoami / mocking / mirror / canary),
~25% managed API with a per-user JWT (so the `app_id` consumer dimension fills in; free tiers
`429` under load), ~12% WAF attacks (`403`), ~3% billed AI calls (only when `ai_enabled`).
`setup()` mints one JWT per `users` entry via the Keycloak password grant.

## Example usage

```hcl
module "loadgen_unified_ingress" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/tools/k6-operator/k8s/loadgen/traefik-hub?ref=v6.2.0"

  namespace              = "monitoring"
  domain                 = "unified.demo.traefik.ai"
  keycloak_url           = "https://keycloak.unified.demo.traefik.ai/realms/traefik/protocol/openid-connect/token"
  keycloak_client_secret = var.keycloak_client_secret
  users                  = [{ username = "acme-1", password = "topsecretpassword" }]
}
```

## Prerequisites

- A working Kubernetes cluster with the `kubectl` provider configured.
- The k6 Operator installed in-cluster (see `tools/k6-operator/k8s`).
- A reachable Keycloak realm with the configured client (direct-access grants enabled).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | ~> 1.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | ~> 1.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubectl_manifest.unified_traffic_configmap](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.unified_traffic_testrun](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain"></a> [domain](#input\_domain) | Base demo domain (e.g. unified.demo.traefik.ai). The scenario derives every route host from it. | `string` | n/a | yes |
| <a name="input_keycloak_client_secret"></a> [keycloak\_client\_secret](#input\_keycloak\_client\_secret) | Keycloak client secret for the password grant. | `string` | n/a | yes |
| <a name="input_keycloak_url"></a> [keycloak\_url](#input\_keycloak\_url) | Keycloak token endpoint (…/realms/<realm>/protocol/openid-connect/token). setup() mints one JWT per user via the password grant. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the TestRun + ConfigMap (the k6 operator must watch it). | `string` | n/a | yes |
| <a name="input_users"></a> [users](#input\_users) | Consumer users the scenario authenticates as. Each request to the managed API picks one at random, so its group claim (app\_id) shows up per-consumer in the dashboards. | <pre>list(object({<br/>    username = string<br/>    password = string<br/>  }))</pre> | n/a | yes |
| <a name="input_ai_enabled"></a> [ai\_enabled](#input\_ai\_enabled) | Run the AI-gateway traffic scenario (rotates the openai/anthropic model lists). OFF by default: these are billed per call. Kept low-rate (ai\_rpm) + small (ai\_max\_tokens), and the gateway's Redis budget self-caps spend. | `bool` | `false` | no |
| <a name="input_ai_max_tokens"></a> [ai\_max\_tokens](#input\_ai\_max\_tokens) | Max output tokens per AI call. Small by default to cap real spend. | `number` | `32` | no |
| <a name="input_ai_rpm"></a> [ai\_rpm](#input\_ai\_rpm) | AI requests per MINUTE across all models/providers (constant arrival rate). Low by default for cost control — the dashboard inflates the displayed token/spend numbers separately. | `number` | `6` | no |
| <a name="input_anthropic_models"></a> [anthropic\_models](#input\_anthropic\_models) | Anthropic models the AI scenario rotates through (sent to /v1/messages). Needs the gateway to inject the platform key (enable\_messages\_api\_passthrough\_auth = false). | `list(string)` | <pre>[<br/>  "claude-haiku-4-5",<br/>  "claude-sonnet-4-5",<br/>  "claude-sonnet-4-6",<br/>  "claude-opus-4-1",<br/>  "claude-opus-4-8"<br/>]</pre> | no |
| <a name="input_duration"></a> [duration](#input\_duration) | How long the test runs (k6 duration string, e.g. 2h). | `string` | `"2h"` | no |
| <a name="input_keycloak_client_id"></a> [keycloak\_client\_id](#input\_keycloak\_client\_id) | Keycloak client id used for the password grant. | `string` | `"traefik"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the k6 TestRun + its script ConfigMap. | `string` | `"traefik-hub-traffic"` | no |
| <a name="input_openai_models"></a> [openai\_models](#input\_openai\_models) | OpenAI models the AI scenario rotates through (sent to /v1/responses; the gateway allows model override). Cost-managed: keep to cheap chat models. | `list(string)` | <pre>[<br/>  "gpt-4o-mini",<br/>  "gpt-4o",<br/>  "gpt-4.1-mini",<br/>  "gpt-4.1-nano",<br/>  "gpt-4o-2024-08-06"<br/>]</pre> | no |
| <a name="input_parallelism"></a> [parallelism](#input\_parallelism) | k6 TestRun parallelism (number of runner pods the load is split across). | `number` | `1` | no |
| <a name="input_vus"></a> [vus](#input\_vus) | Concurrent virtual users (controls aggregate request rate). | `number` | `20` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
