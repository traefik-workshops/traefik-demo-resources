# config-server/git

Deploys the `git-config-server` (image: `ghcr.io/traefik-workshops/git-config-server`, built from [`./image`](./image)) as a Deployment + Service, with a Traefik `IngressRoute` at `git.<domain>` so spokes reach the config repo over the hub's public entrypoint.

Two paths:

- **Write (terraform):** set `files = { "<path>" = <content> }` and every apply pushes the desired tree into `config.git` (one commit; tunneled over `kubectl port-forward`, so it works before the `git.<domain>` DNS record or cert exist). Changing routing intent = re-running this push — never replacing a gateway VM.
- **Read (spokes):** a post-receive hook publishes the pushed tree RAW at `https://git.<domain>/config/<path>` (`raw_base_url` output). Point a Hub provider's `configEndpoint` (gce / oci / ociContainerInstances / vsphere — base services the provider injects discovered servers into) or Traefik's own `--providers.http.endpoint` at a file under it; the provider polls and hot-reloads on its own interval.

```hcl
module "config_server" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/config-server/git?ref=v6.2.0"

  namespace          = kubernetes_namespace_v1.traefik.metadata[0].name
  ingress_host       = "git.${var.domain}"
  kubeconfig_context = "gke-${var.cluster_name}"

  files = {
    "vm/dynamic.yaml" = local.vm_base_config # -> https://git.<domain>/config/vm/dynamic.yaml
  }
}
```

## Rebuilding the image

No CI builds this image — publish it by hand from [`./image`](./image), and **build it from this source**. The org image was once produced by re-tagging an older personal-namespace image rather than rebuilding, so it silently predated the read half above: pushes landed, `/config/<path>` 404'd, and every spoke's `configEndpoint` got nothing. Tag `:latest` **and** an immutable `:v<library-release>` so consumers can pin.

```sh
cd image
docker buildx build --platform linux/amd64 --provenance=false \
  -t ghcr.io/traefik-workshops/git-config-server:latest \
  -t ghcr.io/traefik-workshops/git-config-server:vX.Y.Z --push .
docker buildx imagetools inspect ghcr.io/traefik-workshops/git-config-server:latest # confirm registry-side
```

`linux/amd64` only — every hub cluster that runs this is x86 (GKE default nodes, OKE `VM.Standard.E4.Flex`, vSphere). A build that merely completes proves nothing; verify the read half against the pushed image before trusting it:

```sh
docker run -d --name gcs -p 18080:80 ghcr.io/traefik-workshops/git-config-server:latest
git clone http://127.0.0.1:18080/config.git /tmp/cfg && mkdir -p /tmp/cfg/vm
echo 'http: {}' > /tmp/cfg/vm/dynamic.yaml
git -C /tmp/cfg add -A && git -C /tmp/cfg commit -qm sync && git -C /tmp/cfg push -q origin HEAD:main
curl -i http://127.0.0.1:18080/config/vm/dynamic.yaml # MUST be 200 with that body, not 404
```

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

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_deployment_v1.git](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment_v1) | resource |
| [kubernetes_service_v1.git](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1) | resource |
| [null_resource.ingressroute](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.push](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ingress_host"></a> [ingress\_host](#input\_ingress\_host) | Host the repo is served at — git.<domain>. Spokes clone https://<this>/config.git; terraform pushes to the same. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy into (the demo's traefik namespace, so it shares the hub's ingress). | `string` | n/a | yes |
| <a name="input_files"></a> [files](#input\_files) | The config repo's desired content: repo path -> file content (e.g. { "vm/dynamic.yaml" = yamlencode(...) }). Non-empty makes terraform PUSH the tree on every content change — one commit replacing the repo's previous tree — and the post-receive hook publishes it raw at https://<ingress\_host>/config/<path>, which is what a Hub provider's configEndpoint polls. The push rides a kubectl port-forward straight to the Service, so it needs neither the git.<domain> DNS record nor the ingress cert to be ready — a fresh standup can push before dns-traefiker/ACME converge. This is the GitOps write path: changing routing intent re-runs only this push, never a gateway VM. | `map(string)` | `{}` | no |
| <a name="input_image"></a> [image](#input\_image) | The git-config-server image (built from terraform/config-server/git/image). The default is a MUTABLE tag, so the Deployment pulls it Always — a rebuild has to actually reach the nodes, and a cached stale layer once served the git repo without the raw /config/ read path at all. Pin :vX.Y.Z (published alongside each library release) or a @sha256 digest for a reproducible apply. | `string` | `"ghcr.io/traefik-workshops/git-config-server:latest"` | no |
| <a name="input_ingress_entrypoint"></a> [ingress\_entrypoint](#input\_ingress\_entrypoint) | Traefik entrypoint the IngressRoute binds — the hub's public HTTPS entrypoint (websecure), so spokes reach it exactly like collector.<domain>. | `string` | `"websecure"` | no |
| <a name="input_kubeconfig_context"></a> [kubeconfig\_context](#input\_kubeconfig\_context) | kubectl context for the IngressRoute local-exec apply and the config push port-forward — the ambient context the compute module merges (k3s-<vm\_name> / gke-<cluster> / oke-<cluster>). Empty = ambient default context (fine for a single demo; parallel standups MUST pin it). | `string` | `""` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the git-config-server Deployment/Service/IngressRoute. | `string` | `"git-config-server"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_raw_base_url"></a> [raw\_base\_url](#output\_raw\_base\_url) | Base URL the pushed tree is served RAW under — https://git.<domain>/config. A Hub provider's configEndpoint is <this>/<path-in-files> (the URL path's extension picks the decoder: yaml default / json / toml). |
| <a name="output_repo_url"></a> [repo\_url](#output\_repo\_url) | The clone/push URL for the config repo — https://git.<domain>/config.git. Spokes pull from it; terraform pushes to it. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | In-cluster Service name (for anything that reaches the repo without going through ingress). |
<!-- END_TF_DOCS -->