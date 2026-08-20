# compute/nutanix/nkp/kommander

Provisions a Floating IP for the Kommander/Traefik LoadBalancer service on an NKP cluster and wires the in-cluster `LoadBalancer` Service to it.

## Example usage

```hcl
module "kommander" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/nutanix/nkp/kommander?ref=v6.3.1"

  external_subnet_uuid = var.external_subnet_uuid
  vpc_uuid             = var.vpc_uuid
}
```

## Prerequisites

- A working NKP cluster (see `compute/nutanix/nkp`).
- `kubernetes` and `kubectl` providers configured against the NKP cluster.

## Notes

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.14 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.27 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | >= 1.14 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.27 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubectl_manifest.traefik_app_deployment](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.traefik_overrides](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubernetes_resource.traefik](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/resource) | data source |

## Inputs

No inputs.

## Outputs

No outputs.
<!-- END_TF_DOCS -->
