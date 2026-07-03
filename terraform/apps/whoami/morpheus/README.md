# apps/whoami/morpheus

Provisions one or more Traefik `whoami` instances on **HPE Morpheus** (MVM — the KVM compute type of **VM Essentials / HVM** and full Morpheus) — the on-prem sibling of `apps/whoami/ec2` / `apps/whoami/azure-vm` / `apps/whoami/vsphere`, reusing the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `docker.io/zalbiraw/whoami`). Each replica is one small `hpe_morpheus_instance` (on an MVM cloud; `config_hvm` carries the KVM placement) provisioned from an existing instance type/layout/plan.

## The workload config is dotted tags (the cloud-style model, on-prem)

Morpheus instance **Tags** are free-form name/value pairs — no central registration (vSphere's problem), no line-format Notes (Proxmox's) — so the Traefik Hub `morpheus` provider reads **every `traefik.*` tag as a label**, exactly like the EC2/Azure/OCI dotted-tag model:

```
traefik.enable                                        = "true"
traefik.http.services.whoami.loadbalancer.server.port = "80"
```

This module takes a `traefik_labels` map per app and sets it 1:1 as instance tags. Full label maps ride the tags, so multi-service tricks (several `loadbalancer.strategy` definitions over the same instances) work unchanged. Morpheus **labels** (plain strings) are a separate system: the provider's `constraints` match them as `label=true` pairs **plus a synthesized `name` pseudo-label** (the instance name) — but the `HPE/hpe` terraform provider **cannot set them** (`hpe_morpheus_instance` has no labels attribute as of v1.5.0; gomorpheus's `mvm_instance` did), so apply labels in the appliance; `morpheus_labels` / per-app `labels` must stay empty (validated). Port fallback: with no `server.port` label the provider falls back to the **lowest port declared in the instance's connection info** (layout-declared, not workload-declared) — set the label explicitly.

## Bootstrap is a Morpheus provisioning workflow (read this)

The `HPE/hpe` terraform provider has **no user-data / cloud-config passthrough** on its instance resource (verified against the v1.5.0 schema; neither did gomorpheus), so the composed cloud-init payload can't ride cloud-init here. Instead each app's rendered `#cloud-config` is **converted in terraform** (`yamldecode`: `write_files` → heredocs, `runcmd` → tolerated sequential entries, matching cloud-init's semantics) into a shell script delivered as an `hpe_morpheus_task_shell_script` in a `postProvision` `hpe_morpheus_workflow_provisioning`, executed on each instance by the **Morpheus agent**. Consequences: `config_hvm.no_agent` stays false (the provider default is agentless); the layout must boot a **cloud-init-enabled Linux image** (agent-installable); bootstrap changes recreate the instances (`replace_triggered_by`); the template's `users`/`chpasswd` access conveniences are **not** applied (Morpheus's own provisioning covers access); task/workflow names are `<name_prefix>-<app>-bootstrap`, unique per appliance.

## Example usage

```hcl
module "whoami_morpheus" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/apps/whoami/morpheus?ref=v4.3.0"

  cloud              = "hvm-cloud"
  group              = "demo"
  instance_type      = "Ubuntu"
  instance_layout    = "Single KVM VM"
  plan               = "1 CPU, 2GB Memory"
  resource_pool_name = "hvm-cluster-01"

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-morpheus" # body shows `Name: whoami-morpheus`
      traefik_labels = {
        "traefik.enable"                                        = "true"
        "traefik.http.services.whoami.loadbalancer.server.port" = "80" # set it — the connection-info fallback is layout-declared
      }
    }
  }
}
```

## Prerequisites

- A Morpheus appliance (**VM Essentials / HVM** or full Morpheus) with an MVM cloud, group, Ubuntu-style instance type/layout (cloud-init-enabled, agent-installable) and a small service plan.
- Provider credentials allowed to create library tasks/workflows and provision instances; DHCP on the network; outbound internet from the instances (docker pulls).

## Notes

- The `instances` output exposes each instance's `private_ip` (`connection_info[0]`, the primary connection address) — the Traefik child dials these in-network; the provider's `private` and `public` ipModes both resolve to this same primary connection address on-prem (`ipv6` picks the first IPv6 one).
- Per-instance ipMode override: the `traefik.morpheus.ipmode` tag.
- MIGRATED from the community-deprecated `gomorpheus/morpheus` provider (EOL Aug 2026) to the official `HPE/hpe` provider (`~> 1.5`). One functional loss: `hpe_morpheus_instance` has **no `labels` attribute** (v1.5.0), so `morpheus_labels` and per-app `labels` must stay empty (validated) — set Morpheus labels in the appliance instead. `plan_provision_type` is now the provision type **code** (`"kvm"`), not the name (`"KVM"`). State from gomorpheus deployments does not migrate — plan on recreating.
