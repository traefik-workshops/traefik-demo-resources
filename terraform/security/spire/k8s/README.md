# security/spire/k8s

Deploys SPIRE (the SPIFFE Runtime Environment) on Kubernetes to issue SVIDs for SPIFFE-mTLS multicluster uplinks.

It installs the [`spiffe/helm-charts-hardened`](https://github.com/spiffe/helm-charts-hardened)
charts — `spire-crds` then the `spire` umbrella (spire-server + spire-agent + spiffe-csi-driver +
spire-controller-manager) — issuing **SVIDs** (workload identities) that Traefik consumes to
establish **SPIFFE-mTLS** on Hub multicluster uplinks.

This is workload identity, **not** a user IdP — so it does not follow the `users` /
`user_pool_id` IdP convention in [`../../README.md`](../../README.md). Pair it with
[`keycloak/k8s`](../keycloak/k8s) (user auth) rather than replacing it.

## What it gives a consumer

- A trust domain (`var.trust_domain`) rooting every SVID in the cluster.
- A Workload API socket (via the `csi.spiffe.io` CSI driver) that a pod mounts at
  `workload_api_socket_path` — Traefik points `--spiffe.workloadAPIAddress` at it.
- Optional **federation** bundle endpoint (`enable_federation`) so peer trust domains in
  other clusters/clouds can fetch this cluster's bundle and verify its SVIDs.

## Usage

```hcl
module "spire" {
  source = "../../terraform/security/spire/k8s" # demos use relative sources

  trust_domain      = "eks.traefik-hub"
  cluster_name      = "eks-hub"
  enable_federation = true # expose the bundle endpoint for cross-cluster mTLS
}
```

The consumer then:

1. Mounts the `csi.spiffe.io` volume into the Traefik pod at `workload_api_socket_path` and
   sets `--spiffe.workloadAPIAddress=unix://<path>` (a `ClusterSPIFFEID` registers Traefik).
2. On the parent, sets each child's uplink
   `serversTransport.spiffe.ids = ["spiffe://<child-trust-domain>/…"]`.
3. For cross-cluster trust, applies a `ClusterFederatedTrustDomain` per peer (managed by the
   demo, since each points at the peer's externally-exposed `federation_bundle_endpoint`).

## Notes

- Requires the `helm` and `kubernetes` providers configured against the target cluster (see
  `compute/<cloud>/<cluster>` outputs).
- CRDs install as a separate release (`<name>-crds`) before the umbrella chart.
- Chart versions are pinned (`spire` `0.29.0`, `spire-crds` `0.5.0`); bump deliberately.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.27 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.27 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.crds](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.this](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ca_subject"></a> [ca\_subject](#input\_ca\_subject) | Subject of the SPIRE server's self-signed CA. | <pre>object({<br/>    country      = string<br/>    organization = string<br/>    common_name  = string<br/>  })</pre> | <pre>{<br/>  "common_name": "spire",<br/>  "country": "US",<br/>  "organization": "Traefik Demo"<br/>}</pre> | no |
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | Helm chart repository URL for the SPIRE hardened charts. | `string` | `"https://spiffe.github.io/helm-charts-hardened/"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Logical cluster name SPIRE uses for node attestation and SVID paths. | `string` | `"demo"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Create the namespace before installing. Set false if the caller already manages it. | `bool` | `true` | no |
| <a name="input_enable_federation"></a> [enable\_federation](#input\_enable\_federation) | Expose the SPIRE server federation bundle endpoint so peer trust domains can fetch this cluster's trust bundle. Required for cross-cluster SPIFFE-mTLS uplinks; pair with ClusterFederatedTrustDomain resources (managed by the consuming demo) pointing at each peer's bundle endpoint. | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Helm release name for the SPIRE umbrella chart (server + agent + CSI driver + controller-manager). | `string` | `"spire"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to install SPIRE into. | `string` | `"spire"` | no |
| <a name="input_spire_chart_version"></a> [spire\_chart\_version](#input\_spire\_chart\_version) | Pinned version of the `spire` umbrella chart (spiffe/helm-charts-hardened). | `string` | `"0.29.0"` | no |
| <a name="input_spire_crds_chart_version"></a> [spire\_crds\_chart\_version](#input\_spire\_crds\_chart\_version) | Pinned version of the `spire-crds` chart (spiffe/helm-charts-hardened). | `string` | `"0.5.0"` | no |
| <a name="input_trust_domain"></a> [trust\_domain](#input\_trust\_domain) | SPIFFE trust domain that roots every SVID this server issues (e.g. "eks.example.org"). Each cluster in a federation MUST use a distinct trust domain. | `string` | `"example.org"` | no |
| <a name="input_values"></a> [values](#input\_values) | Additional Helm values for the `spire` chart, deep-merged on top of the module's base values (trust domain, cluster name, CA subject, federation). Use for node attestors (e.g. aws\_iid), ClusterSPIFFEID defaults, and resource tuning. | `any` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Logical cluster name used for node attestation and SVID paths. |
| <a name="output_federation_bundle_endpoint"></a> [federation\_bundle\_endpoint](#output\_federation\_bundle\_endpoint) | In-cluster federation bundle endpoint peers fetch this cluster's trust bundle from (empty unless enable\_federation). Expose externally for cross-cloud federation. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace SPIRE is installed into. |
| <a name="output_trust_domain"></a> [trust\_domain](#output\_trust\_domain) | SPIFFE trust domain rooting every SVID this server issues. |
| <a name="output_workload_api_socket_path"></a> [workload\_api\_socket\_path](#output\_workload\_api\_socket\_path) | In-pod path where the spiffe-csi-driver (csi.spiffe.io) mounts the Workload API socket. Mount that CSI volume here in a consumer pod and point Traefik at --spiffe.workloadAPIAddress=unix://<this>. |
<!-- END_TF_DOCS -->
