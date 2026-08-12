# cloud-init-snippets/

Shared cloud-init fragments rendered by BOTH `terraform/traefik/cloud-init`
(the gateway template) and `terraform/apps/whoami/cloud-init` (the backend
template). `templatefile()` has no include, so the cloud-init modules render
each snippet first and inject the result as a pre-rendered variable — snippet
text is never re-interpolated by the outer template.

- `docker-install.sh.tpl` — the dnf/yum/apt install matrix (an apt-only
  install silently broke Amazon Linux spokes, 2026-07). No variables.
- `otlp-collector-gate.sh.tpl` — the bounded wait for the OTel collector to
  accept OTLP writes before starting telemetry-emitting services (exporters
  that start against a dead endpoint stay dark). Variables: `otlp_address`,
  `rounds` (× 10s). `compute/aws/ecs` renders it too, as a Fargate sidecar
  rather than into cloud-init.

## The gate's contract

It defines `otlp_collector_gate()`, calls it once, and leaves the verdict in
`$otlp_gate_status` (0 = the collector accepted a write, 1 = budget exhausted,
loudly on stderr). It NEVER runs `exit`, and its last statement is an
assignment, so the snippet always ends with status 0. That is deliberate: on
the VM legs this text is pasted inline into a cloud-init `runcmd` entry, where
an `exit` would abandon the rest of the boot — the gateway's own `systemctl
enable --now traefik-hub` runs after it.

Callers decide what exhaustion means, and the two families differ on purpose:

- The cloud-init templates read `$otlp_gate_status` only to log it and carry
  on. A collector that never arrives must degrade a VM to "boots, reports
  late", never to a half-provisioned host with no gateway on it.
- `compute/aws/ecs` appends `exit $otlp_gate_status` and pairs it with
  `dependsOn: SUCCESS`, so an exhausted gate stops the task. There, "started
  anyway" means an exporter dark for the life of the task with no second boot
  to put it right — failing open is the failure, not the fallback.

Pick `rounds` against 1800s: the SOA MINIMUM on `traefik.ai`, and therefore
the longest a resolver may keep serving a cached NXDOMAIN for a record that
has since been published. The VM legs pass 180 — exactly 1800s, no margin —
which is only survivable because they fail open. Any caller that makes
exhaustion fatal must budget past it (ECS uses 270 = 2700s).

Editing a snippet re-renders every VM's user_data (the proxmox snippet
filename embeds its md5 → gateway VM replacement on next apply). Treat edits
like gateway-template edits: check for live on-prem state first.

## KEEP THESE FILES LEAN — comments here are shipped as user data

Every byte of a snippet is pasted inline into cloud-init user data, and **EC2
caps user data at 16384 bytes** (Alibaba ECS caps it at the same 16KB; Azure is
64KB, GCP 256KB, OCI 32KB). Prose belongs in THIS file, not in the `.tpl`.

This is not hypothetical. v6.2.8 documented the gate's contract and budget
rationale *inside* `otlp-collector-gate.sh.tpl`, growing it 743 → 3901 bytes —
**3158 bytes of pure comment**. aws-unified-ingress had 2164 bytes of headroom,
so the next apply died deterministically at plan-known size:

```
Error: creating EC2 Instance: RunInstances ... InvalidParameterValue:
       User data is limited to 16384 bytes
```

Measured on the same state, same domain, only the snippet swapped: v6.2.6 →
14220 B (fits), v6.2.8 → 17580 B (over by 1196), lean → 14646 B (fits). The
behaviour was identical in all three; only the documentation differed. v6.2.9
moved the prose here and kept every behavioural element.

Two things follow. Explaining a snippet is *more* valuable than explaining most
code — it runs once, unattended, on a host nobody will shell into — so write
that explanation, just write it here. And if you add to a snippet, check the
rendered size against 16384 before tagging: `terraform plan` surfaces it, but
only for a demo that was already near the line.
