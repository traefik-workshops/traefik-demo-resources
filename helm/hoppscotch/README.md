# helm/hoppscotch

Self-hosted Hoppscotch with multi-collection nginx serving

- **Chart version:** `6.2.8` (slaved to the repo tag — see [`../AGENTS.md`](../AGENTS.md))
- **App version:** `2026.5.0`

## Install

```bash
helm install my-hoppscotch oci://ghcr.io/traefik-workshops/hoppscotch --version 6.2.8
```

From source (for development against this repo):

```bash
cd helm/hoppscotch
helm dep update
helm install my-hoppscotch .
```

## Conventions

See [`../AGENTS.md`](../AGENTS.md) for chart conventions and [the root `AGENTS.md`](../../AGENTS.md) for repo-wide rules.

<!-- BEGIN_HELM_DOCS -->

## Requirements

| Name | Version |
|------|---------|
| kubernetes | `>= 1.27.0-0` |
| helm | (apiVersion v2) |

## Values

| Key | Default |
|-----|---------|
| `global` | (object) |
| `global.domain` | `""` |
| `subdomain` | `"test"` |
| `host` | `""` |
| `image` | `"hoppscotch/hoppscotch:2026.5.0"` |
| `jwtSecret` | `"demo0demo0demo0demo0demo0demojwt"` |
| `sessionSecret` | `"demo0demo0demo0demo0demo0demoses"` |
| `dataEncryptionKey` | `"demo0demo0demo0demo0demo0demodek"` |
| `entryPoints` | (list, 1 items) |
| `collections` | `[]` |

<!-- END_HELM_DOCS -->
