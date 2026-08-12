# compute/alibaba/ack

Managed ACK (Alibaba Cloud Container Service for Kubernetes) cluster — the Alibaba sibling of `compute/azure/aks` and `compute/oracle/oke`. Joins existing vswitches (e.g. `compute/alibaba/vpc`'s) instead of creating its own network; a default node pool (or per-role pools via `worker_nodes`, with native taints) runs the smallest reliable node size.

ACK kubeconfigs are **client-certificate based** — the credential outputs mirror AKS (`host`, `cluster_ca_certificate`, `client_certificate`, `client_key`) plus the full `kubeconfig` (sensitive), parsed from the `alicloud_cs_cluster_credential` data source the OKE way.

## Example usage

```hcl
module "vpc" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/alibaba/vpc?ref=v6.2.8"

  name = "traefik-demo"
}

module "ack" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/alibaba/ack?ref=v6.2.8"

  cluster_name = "traefik-demo"
  vswitch_ids  = module.vpc.vswitch_ids
}

provider "kubernetes" {
  host                   = module.ack.host
  cluster_ca_certificate = module.ack.cluster_ca_certificate
  client_certificate     = module.ack.client_certificate
  client_key             = module.ack.client_key
}
```

## Prerequisites

- Alibaba Cloud credentials (env vars / profile) with CS, ECS and VPC permissions; the region comes from the configured `alicloud` provider.
- `kubectl` locally when `update_kubeconfig = true` (merges the context as `ack-<cluster_name>`).

## Notes

- `enable_nat_gateway` (default `true`) creates a NAT gateway + SNAT so nodes can pull images — an extra billed resource; disable it when the vswitches already route through one.
- `cluster_spec` defaults to `ack.pro.small`: the Pro control plane is billed hourly, but the Basic `ack.standard` spec is no longer offered in newer regions.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_alicloud"></a> [alicloud](#requirement\_alicloud) | ~> 1.220 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_alicloud"></a> [alicloud](#provider\_alicloud) | ~> 1.220 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [alicloud_cs_kubernetes_node_pool.traefik_demo](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/cs_kubernetes_node_pool) | resource |
| [alicloud_cs_kubernetes_node_pool.worker](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/cs_kubernetes_node_pool) | resource |
| [alicloud_cs_managed_kubernetes.traefik_demo](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/cs_managed_kubernetes) | resource |
| [null_resource.ack_cluster](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [alicloud_cs_cluster_credential.kubeconfig](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/data-sources/cs_cluster_credential) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | ACK cluster name. | `string` | n/a | yes |
| <a name="input_vswitch_ids"></a> [vswitch\_ids](#input\_vswitch\_ids) | Existing vswitch IDs the control plane and node pools join (e.g. compute/alibaba/vpc's vswitch\_ids). The region comes from the configured alicloud provider. | `list(string)` | n/a | yes |
| <a name="input_ack_version"></a> [ack\_version](#input\_ack\_version) | ACK Kubernetes version. Empty = the latest version ACK offers at create time. | `string` | `""` | no |
| <a name="input_cluster_node_count"></a> [cluster\_node\_count](#input\_cluster\_node\_count) | Number of nodes for the cluster. | `number` | `1` | no |
| <a name="input_cluster_node_type"></a> [cluster\_node\_type](#input\_cluster\_node\_type) | Default ECS instance type for cluster nodes (2 vCPU / 4 GB — the smallest ACK reliably accepts). | `string` | `"ecs.c6.large"` | no |
| <a name="input_cluster_spec"></a> [cluster\_spec](#input\_cluster\_spec) | ACK managed cluster spec (ack.pro.small = Pro; some newer regions no longer offer the Basic ack.standard). | `string` | `"ack.pro.small"` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Create a NAT gateway + SNAT so nodes have outbound internet (image pulls). Disable when the vswitches already route through one. | `bool` | `true` | no |
| <a name="input_node_disk_category"></a> [node\_disk\_category](#input\_node\_disk\_category) | System disk category for the nodes. | `string` | `"cloud_essd"` | no |
| <a name="input_node_disk_size"></a> [node\_disk\_size](#input\_node\_disk\_size) | System disk size (GB) for the nodes. | `number` | `40` | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | Pod CIDR (Flannel). Must not overlap the VPC CIDR. | `string` | `"10.244.0.0/16"` | no |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | Existing security group for the cluster's nodes. Empty = ACK creates one. | `string` | `""` | no |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | Service CIDR. Must not overlap the VPC CIDR. | `string` | `"10.96.0.0/16"` | no |
| <a name="input_update_kubeconfig"></a> [update\_kubeconfig](#input\_update\_kubeconfig) | Update kubeconfig after cluster creation | `bool` | `true` | no |
| <a name="input_worker_nodes"></a> [worker\_nodes](#input\_worker\_nodes) | Worker node pool definitions. Each entry creates a dedicated node pool with the given label and taint (ACK supports native taints, applied at the pool). | <pre>list(object({<br/>    label = string<br/>    taint = string<br/>    count = number<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_client_certificate"></a> [client\_certificate](#output\_client\_certificate) | ACK cluster client certificate (ACK kubeconfigs are cert-based — there is no token) |
| <a name="output_client_key"></a> [client\_key](#output\_client\_key) | ACK cluster client key |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | ACK cluster CA certificate |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | ACK cluster ID |
| <a name="output_host"></a> [host](#output\_host) | ACK cluster host (public API server endpoint) |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | ACK cluster kubeconfig |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC the cluster landed in — ECS/ECI spokes (apps/whoami/alibaba-*, traefik/alibaba-*) join it |
<!-- END_TF_DOCS -->
