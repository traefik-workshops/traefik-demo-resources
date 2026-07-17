# cloud-init-snippets/

Shared cloud-init fragments rendered by BOTH `terraform/traefik/cloud-init`
(the gateway template) and `terraform/apps/whoami/cloud-init` (the backend
template). `templatefile()` has no include, so the cloud-init modules render
each snippet first and inject the result as a pre-rendered variable — snippet
text is never re-interpolated by the outer template.

- `docker-install.sh.tpl` — the dnf/yum/apt install matrix (an apt-only
  install silently broke Amazon Linux spokes, 2026-07). No variables.
- `otlp-collector-gate.sh.tpl` — the bounded 30-min wait for the OTel
  collector to accept OTLP writes before starting telemetry-emitting services
  (exporters that start against a dead endpoint stay dark). Variables:
  `otlp_address`.

Editing a snippet re-renders every VM's user_data (the proxmox snippet
filename embeds its md5 → gateway VM replacement on next apply). Treat edits
like gateway-template edits: check for live on-prem state first.
