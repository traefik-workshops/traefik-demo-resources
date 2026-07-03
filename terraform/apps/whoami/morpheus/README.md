# apps/whoami/morpheus

Provisions one or more Traefik `whoami` instances on **HPE Morpheus** (MVM — the KVM compute type of **VM Essentials / HVM** and full Morpheus) — the on-prem sibling of `apps/whoami/ec2` / `apps/whoami/azure-vm` / `apps/whoami/vsphere`, reusing the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `docker.io/zalbiraw/whoami`). Each replica is one small `morpheus_mvm_instance` provisioned from an existing instance type/layout/plan.

## The workload config is dotted tags (the cloud-style model, on-prem)

Morpheus instance **Tags** are free-form name/value pairs — no central registration (vSphere's problem), no line-format Notes (Proxmox's) — so the Traefik Hub `morpheus` provider reads **every `traefik.*` tag as a label**, exactly like the EC2/Azure/OCI dotted-tag model:

```
traefik.enable                                        = "true"
traefik.http.services.whoami.loadbalancer.server.port = "80"
```

This module takes a `traefik_labels` map per app and sets it 1:1 as instance tags. Full label maps ride the tags, so multi-service tricks (several `loadbalancer.strategy` definitions over the same instances) work unchanged. Morpheus **labels** (plain strings) are a separate system: the provider's `constraints` match them as `label=true` pairs **plus a synthesized `name` pseudo-label** (the instance name) — pass them via `morpheus_labels` / per-app `labels`. Port fallback: with no `server.port` label the provider falls back to the **lowest port declared in the instance's connection info** (layout-declared, not workload-declared) — set the label explicitly.

## Bootstrap is a Morpheus provisioning workflow (read this)

The `gomorpheus/morpheus` terraform provider has **no user-data / cloud-config passthrough** on its instance resources, so the composed cloud-init payload can't ride cloud-init here. Instead each app's rendered `#cloud-config` is **converted in terraform** (`yamldecode`: `write_files` → heredocs, `runcmd` → tolerated sequential entries, matching cloud-init's semantics) into a shell script delivered as a `morpheus_shell_script_task` in a `postProvision` `morpheus_provisioning_workflow`, executed on each instance by the **Morpheus agent**. Consequences: `skip_agent_install` stays false; the layout must boot a **cloud-init-enabled Linux image** (agent-installable); bootstrap changes recreate the instances (`replace_triggered_by`); the template's `users`/`chpasswd` access conveniences are **not** applied (Morpheus's own provisioning covers access); task/workflow names are `<name_prefix>-<app>-bootstrap`, unique per appliance.

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
      labels   = ["traefik-demo"]  # Morpheus labels — constraint matching
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

- The `instances` output exposes each instance's `private_ip` (`primary_ip_address`) — the Traefik child dials these in-network; the provider's `private` and `public` ipModes both resolve to this same primary connection address on-prem (`ipv6` picks the first IPv6 one).
- Per-instance ipMode override: the `traefik.morpheus.ipmode` tag.
- The `gomorpheus/morpheus` provider is community-deprecated in favor of the official `HPE/hpe` provider (EOL announced Aug 2026) — pinned `~> 0.14` here until the repo migrates.
