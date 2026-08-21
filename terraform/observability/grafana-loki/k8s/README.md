# observability/grafana-loki/k8s

Deploys Grafana Loki on Kubernetes via Helm.

## Example usage

```hcl
module "loki" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/observability/grafana-loki/k8s?ref=v6.4.0"

  name      = "loki"
  namespace = "observability"
}
```

## Prerequisites

- A working Kubernetes cluster with the `helm` provider configured.

## Storage

Ephemeral by default. Left at chart defaults this release is the only thing in the
observability stack that asks for storage — three PVCs (`storage-loki-0` at 10Gi, plus
the bundled MinIO's `export-0`/`export-1` at 5Gi each) — and on a managed cluster each
one becomes a real, billed cloud disk that `terraform destroy` leaves behind: the
reclaim is an asynchronous CSI call that loses the race with the cluster teardown, and
terraform owns no resource for it. A demo lives for hours, so `persistence = false`
(the default) mounts both stores as `emptyDir` at the same paths instead — no PVC, no
disk, nothing to leak. Set `persistence = true` only for an install meant to outlive
its pods, and only where something reclaims the disks.

At the default setting no `StorageClass` is needed at all, which also removes the
`atomic = true` rollback a cluster with no default provisioner would otherwise cause.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.loki](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the Grafana deployment | `string` | n/a | yes |
| <a name="input_extra_values"></a> [extra\_values](#input\_extra\_values) | Extra values to pass to the Grafana deployment. | `any` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the loki release | `string` | `"loki"` | no |
| <a name="input_persistence"></a> [persistence](#input\_persistence) | Back the single-binary Loki and its bundled MinIO with PersistentVolumeClaims instead of emptyDir. Default FALSE — see the teardown note in main.tf: a PVC here becomes a real cloud disk that survives `terraform destroy`. Set true only for an install meant to outlive its pods, and only where something reclaims the disks. | `bool` | `false` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for the Grafana deployment. | <pre>list(object({<br/>    key      = string<br/>    operator = string<br/>    value    = string<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
