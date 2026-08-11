# tools/redis/k8s

Deploys Redis on Kubernetes via Helm with a configurable password and replica count.

## Example usage

```hcl
module "redis" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/tools/redis/k8s?ref=v6.1.6"

  name      = "redis"
  namespace = "data"
}
```

## Prerequisites

- A working Kubernetes cluster with the `helm` provider configured.

## Storage

Ephemeral by default. Left at chart defaults this StatefulSet binds one 8Gi RWO claim
(`data-<release>-0`, mounted at `/data`), which on a managed cluster is a real, billed
cloud disk — and this chart's `persistentVolumeClaimRetentionPolicy` ships disabled with
`whenDeleted: Retain`, so the claim is not even deleted with the StatefulSet, let alone
the disk behind it. `persistence = false` (the default) makes the chart mount `emptyDir`
at the same `/data` instead.

Losing Redis state on a restart is safe here, which is the part worth being explicit
about. This Redis is **not** the certificate store: Traefik Hub's distributed ACME
accepts Kubernetes secrets or Vault and nothing else, and this library always configures
the Kubernetes one, so an empty Redis can never cause a re-issue — and never a Let's
Encrypt rate limit. What it backs is API Management's plan middleware: rate-limit and
quota counters, which a restart resets to zero and the next request rebuilds.

Set `persistence = true` only for an install meant to outlive its pods, and only where
something reclaims the disk.

## Notes

- Default `password` is a demo value — override it for any non-throwaway deployment.
- `replica_count` renders `replica.replicaCount`, a key the pinned chart (0.4.6) does not
  read — its own key is the top-level `replicaCount`, and only under
  `architecture: replication`. The release is a single instance whatever this is set to.

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
| [helm_release.redis](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the Redis deployment | `string` | n/a | yes |
| <a name="input_extra_values"></a> [extra\_values](#input\_extra\_values) | Extra values to merge into the Helm chart values | `any` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the redis release | `string` | `"traefik"` | no |
| <a name="input_password"></a> [password](#input\_password) | Redis password. DEMO DEFAULT — override per environment. | `string` | `"topsecretpassword"` | no |
| <a name="input_persistence"></a> [persistence](#input\_persistence) | Back Redis's /data with a PersistentVolumeClaim (8Gi RWO) instead of emptyDir. Default FALSE — see the note in main.tf: the claim becomes a real cloud disk that survives `terraform destroy` (this chart even retains it when the StatefulSet goes), and nothing this Redis holds is worth one. It is NOT the ACME store — Hub keeps distributed-ACME certs in Kubernetes secrets or Vault, never Redis — it backs API Management plan rate-limit and quota counters, which a restart resets to zero and the next request rebuilds. | `bool` | `false` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of replicas for the Redis deployment | `number` | `1` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
