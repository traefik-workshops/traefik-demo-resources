# ai/ai-gateway-dependencies/k8s

Installs the in-cluster dependencies required by the AI Gateway demo (Helm-based bundle).

## Example usage

```hcl
module "aigw_deps" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/ai/ai-gateway-dependencies/k8s?ref=v6.6.0"

  namespace = "ai-gateway"
}
```

## Prerequisites

- A working Kubernetes cluster with the `helm` provider configured.

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
| <a name="module_ai_ollama"></a> [ai\_ollama](#module\_ai\_ollama) | ../../ollama/k8s | n/a |
| <a name="module_ai_presidio"></a> [ai\_presidio](#module\_ai\_presidio) | ../../presidio/k8s | n/a |
| <a name="module_ai_weaviate"></a> [ai\_weaviate](#module\_ai\_weaviate) | ../../weaviate/k8s | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the Grafana deployment | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
