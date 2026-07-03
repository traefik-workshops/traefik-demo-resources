# compute/ibm/iks

Provisions a managed IKS (IBM Cloud Kubernetes Service) cluster on VPC gen2 — the IBM sibling of `compute/alibaba/ack` / `compute/oracle/oke`. Joins existing subnets (e.g. `compute/ibm/vpc`'s `subnet_ids`, one zone entry per subnet) instead of creating its own network. Default size: one `bx2.4x16` worker **per zone** (two subnets = 2 workers).

> **New provider**: this is one of the repo's first IBM Cloud modules and introduces the `IBM-Cloud/ibm` Terraform provider (pinned `~> 1.89`).

Credentials are **OKE-style token outputs** (not AKS/ACK client certs): IKS kubeconfigs authenticate with an IAM OAuth token, and the `ibm_container_cluster_config` data source exposes `host`/`ca_certificate`/`token` directly — the canonical IBM pattern for feeding the `kubernetes`/`helm` providers. The token is short-lived; it refreshes on every Terraform read. `kubeconfig` is synthesized from the same trio.

## Example usage

```hcl
module "iks" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/compute/ibm/iks?ref=v4.3.0"

  cluster_name = "traefik-demo"
  subnet_ids   = module.vpc.subnet_ids
}

provider "kubernetes" {
  host                   = module.iks.host
  token                  = module.iks.token
  cluster_ca_certificate = module.iks.cluster_ca_certificate
}
```

## Prerequisites

- IBM Cloud API key with VPC + Kubernetes Service permissions; the region comes from the configured `ibm` provider.
- Existing VPC subnets to join (e.g. `compute/ibm/vpc`'s). Subnets need a public gateway for worker image pulls — `compute/ibm/vpc` attaches one per zone.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_ibm"></a> [ibm](#requirement\_ibm) | ~> 1.89 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_ibm"></a> [ibm](#provider\_ibm) | ~> 1.89 |

## Resources

| Name | Type |
|------|------|
| [ibm_container_vpc_cluster.traefik_demo](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/container_vpc_cluster) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | IKS cluster name. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Existing VPC subnet IDs the cluster joins (e.g. compute/ibm/vpc's subnet\_ids). One zone entry per subnet; all subnets must belong to the same VPC. The region comes from the configured ibm provider. | `list(string)` | n/a | yes |
| <a name="input_cluster_node_count_per_zone"></a> [cluster\_node\_count\_per\_zone](#input\_cluster\_node\_count\_per\_zone) | Number of worker nodes PER ZONE (IKS semantics — one per subnet zone; two subnets x 1 = 2 workers). | `number` | `1` | no |
| <a name="input_cluster_node_type"></a> [cluster\_node\_type](#input\_cluster\_node\_type) | Worker node flavor (4 vCPU / 16 GB — the smallest VPC gen2 flavor IKS reliably accepts). | `string` | `"bx2.4x16"` | no |
| <a name="input_kube_version"></a> [kube\_version](#input\_kube\_version) | IKS Kubernetes version (e.g. 1.32.3). Empty = the IKS default version at create time. | `string` | `""` | no |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource group ID the cluster lands in. Empty = the account's default resource group. | `string` | `""` | no |
| <a name="input_wait_till"></a> [wait\_till](#input\_wait\_till) | Readiness gate the create blocks on (MasterNodeReady \| OneWorkerNodeReady \| IngressReady \| Normal). The default unblocks as soon as one worker is schedulable. | `string` | `"OneWorkerNodeReady"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | IKS cluster CA certificate (PEM) |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | IKS cluster ID |
| <a name="output_crn"></a> [crn](#output\_crn) | IKS cluster CRN — what an IAM trusted profile's compute-resource claim rule (cr\_type "IKS\_SA") scopes on to trust in-cluster workloads |
| <a name="output_host"></a> [host](#output\_host) | IKS cluster host (public API server endpoint) |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | IKS cluster kubeconfig (synthesized from host/CA/token) |
| <a name="output_token"></a> [token](#output\_token) | IKS cluster auth token (IAM OAuth token — short-lived, refreshed on every terraform read) |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC the cluster landed in — VM spokes (apps/whoami/ibm-vpc, traefik/ibm-vpc) join it |
<!-- END_TF_DOCS -->
