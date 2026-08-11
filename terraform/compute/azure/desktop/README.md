# compute/azure/desktop

A generic **Demo Studio recording workstation** on Azure: Ubuntu 24.04 + GNOME + xrdp on a dummy
Xorg pinned to 1920×1080, the full dev toolchain, and the recording stack (ffmpeg, wmctrl, xdotool).
One VM serves any demo's `record-section` — it runs no gateway.

Forked from [`terraform/traefik/azure-vm`](../../../traefik/azure-vm) (VM/NIC/pip/identity/role
skeleton) with the entire Traefik-Hub surface dropped. Provisioned by [`cloud-init/desktop.tpl`](./cloud-init/desktop.tpl).

- **Capture on the VM** (ffmpeg x11grab against the pinned `:10` display); **RDP is watch-only**.
- **Phase A** (default): vanilla Ubuntu + cloud-init (~15 min first boot). **Phase B**: set
  `source_image_id` to a Shared Image Gallery golden image for ~2-min boots + frozen tool versions.
- Lock `source_address_prefix` to your operator IP — the NSG opens SSH (22) + RDP (3389).
- Secrets: prefer the managed identity for Azure; inject the git deploy key / API keys via
  `extra_files` (0600). ElevenLabs runs off the VM — its key never lands here.

Driven by the `vm-standup` / `vm-teardown` skills; consumed via `recording-target.yaml`.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs fills this table: run `terraform-docs --config .terraform-docs.yml terraform/compute/azure/desktop` -->
<!-- END_TF_DOCS -->
