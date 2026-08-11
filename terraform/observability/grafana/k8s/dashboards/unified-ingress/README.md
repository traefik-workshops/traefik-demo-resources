<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.27 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.27 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_config_map_v1.grafana_unified_ingress_dashboard](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | Name of the ConfigMap holding the Unified Ingress dashboard JSON (Grafana's sidecar picks it up by label). | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to create the dashboard ConfigMap in — usually the namespace Grafana watches for dashboard ConfigMaps. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->