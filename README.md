# traefik-demo-resources

The shared infrastructure library behind the [traefik-workshops](https://github.com/traefik-workshops)
demos: **114 Terraform modules** and **7 Helm charts** for standing up Traefik Hub
across clouds, on-prem platforms, and Kubernetes.

- `terraform/` — modules in nine sections: `ai/`, `apps/`, `cloud-init-snippets/`,
  `compute/`, `config-server/`, `observability/`, `security/`, `tools/`, `traefik/`.
  Each leaf module carries its own README with inputs/outputs.
- `helm/` — charts: `ai-gateway`, `airlines`, `dns-traefiker`, `embeddings`,
  `hoppscotch`, `keycloak`, `presidio`. Published as OCI artifacts to
  `ghcr.io/traefik-workshops/<chart>` on every release tag.

## Consuming the Terraform modules

Pin a release tag — modules are consumed straight over git:

```hcl
module "traefik" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/traefik/k8s?ref=v5.0.0&depth=1"
  # ... inputs per the module's README
}
```

## Consuming the Helm charts

Charts are OCI artifacts; pin the chart version:

```hcl
resource "helm_release" "dns_traefiker" {
  chart   = "oci://ghcr.io/traefik-workshops/dns-traefiker"
  version = "5.0.0"
}
```

or with the Helm CLI:

```bash
helm pull oci://ghcr.io/traefik-workshops/keycloak --version 5.0.0
```

## Versioning

The repo releases as a whole: one `vX.Y.Z` tag covers every module and chart, and
chart versions track the tag. Consumers (the
[workshop repos](https://github.com/traefik-workshops)) pin `?ref=` and chart
`version` to a tag and bump deliberately.

## Where things happen

This repo is **content only** — module and chart source. Development, quality
gates, cataloging and releases are driven from a separate control plane; issues
and PRs here are welcome and get validated on their way in.

## License

[Apache-2.0](./LICENSE)
