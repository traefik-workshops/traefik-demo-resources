# config-server/git

Deploys the `git-config-server` (image: `ghcr.io/traefik-workshops/git-config-server`, built from [`./image`](./image)) as a Deployment + Service, with an optional Traefik `IngressRoute` at `git.<domain>` so spokes can clone the config repo over the hub's public entrypoint.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_deployment_v1.git](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment_v1) | resource |
| [kubernetes_service_v1.git](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1) | resource |
| [null_resource.ingressroute](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ingress_host"></a> [ingress\_host](#input\_ingress\_host) | Host the repo is served at — git.<domain>. Spokes clone https://<this>/config.git; terraform pushes to the same. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy into (the demo's traefik namespace, so it shares the hub's ingress). | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | The git-config-server image (built from terraform/config-server/git/image). | `string` | `"ghcr.io/traefik-workshops/git-config-server:latest"` | no |
| <a name="input_ingress_entrypoint"></a> [ingress\_entrypoint](#input\_ingress\_entrypoint) | Traefik entrypoint the IngressRoute binds — the hub's public HTTPS entrypoint (websecure), so spokes reach it exactly like collector.<domain>. | `string` | `"websecure"` | no |
| <a name="input_kubeconfig_context"></a> [kubeconfig\_context](#input\_kubeconfig\_context) | kubectl context for the IngressRoute local-exec apply — the ambient context the k3s module merges (k3s-<vm\_name>). Empty = ambient default context. | `string` | `""` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the git-config-server Deployment/Service/IngressRoute. | `string` | `"git-config-server"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_repo_url"></a> [repo\_url](#output\_repo\_url) | The clone/push URL for the config repo — https://git.<domain>/config.git. Spokes pull from it; terraform pushes to it. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | In-cluster Service name (for anything that reaches the repo without going through ingress). |
<!-- END_TF_DOCS -->