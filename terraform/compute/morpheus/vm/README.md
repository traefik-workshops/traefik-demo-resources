# compute/morpheus/vm

Shared **HPE Morpheus VM** compute module — one `hpe_morpheus_instance` per app replica on an MVM cloud (MVM — the KVM compute type of **HPE VM Essentials / HVM** and full Morpheus; `config_hvm` carries the KVM placement). This is the Morpheus VM analogue of `compute/aws/ec2`: both `traefik/morpheus-vm` (the gateway, one instance) and `apps/whoami/morpheus` (N workloads) compose it, so the instance + its Morpheus placement lookups + the bootstrap delivery live in ONE place.

Provisions from an **existing** cloud / group / instance-type / layout / plan (Morpheus owns those; the module looks them up by name, or takes literal ids on VME where the Library API is 403-gated). Instances are keyed `"<app>-<replica>"` (1-based), matching the ec2 / azure-vm / vsphere siblings.

## Bootstrap is a Morpheus provisioning workflow (read this)

The `HPE/hpe` terraform provider exposes **no user-data / cloud-config passthrough** on its instance resource (verified against the v1.5.0 schema; neither did gomorpheus's `morpheus_mvm_instance`). So the module rides Morpheus's own provisioning pipeline: the caller's already-rendered bootstrap **shell script** (passed in as `apps.<key>.user_data` — OPAQUE to this module) becomes an `hpe_morpheus_task_shell_script` (`execute_target = "resource"`, sudo) wrapped in an `hpe_morpheus_workflow_provisioning` (`postProvision`) attached to the instance via `task_set_id` — the **Morpheus agent** runs it as provisioning completes. Consequences:

- One task + workflow **per app** (replicas share it); named by the caller-supplied `bootstrap_name` (appliance-level library items — unique per appliance).
- `config_hvm.no_agent` stays **false** (the provider default is `true`/agentless) — the agent executes the bootstrap, so the layout must boot a cloud-init-enabled Linux image.
- The workflow runs at provision time only; every instance `replace_triggered_by`s the task set, so a bootstrap change **recreates the instances** (same first-boot-only story as cloud-init).
- On **HPE VM Essentials** `features.workflows` is off (`POST /api/task-sets` 403s). Set `enable_provisioning_workflow = false` and execute the task directly instead (`POST /api/tasks/{id}/execute` is ungated); the caller owns triggering it and reads `bootstrap_task_ids`.

## Config is instance TAGS

The workload config is dotted Traefik labels as name/value instance **tags** (the EC2/Azure-style tag model, on-prem): each app's `tags` map lands 1:1 as instance tags and the Traefik Hub morpheus provider reads every `traefik.*` tag. Morpheus LABELS (plain strings) are a separate system the provider's `constraints` match — but `hpe_morpheus_instance` has **no `labels` attribute** (v1.5.0), so labels can't be set from terraform; the callers validate they stay empty. Set labels in the appliance instead.

## Static IPs

`apps.<key>.private_ips` pins the NIC per replica index: `private_ips[replica]` sets `ip_mode = static` / `ip_address` (verified present on `hpe_morpheus_instance` v1.5.0) so the address is plan-known and stable across recreation (a parent dialing a child never goes stale). Empty (or a short list) leaves the unpinned replicas on DHCP / the layout's IP pool — the default behavior. Requires `network` set.

## Example usage

```hcl
module "compute" {
  source = "../../compute/morpheus/vm"

  cloud              = "hvm-cloud"
  group              = "demo"
  instance_layout    = "Single KVM VM"
  plan               = "2 CPU, 4GB Memory"
  resource_pool_name = "hvm-cluster-01"

  apps = {
    whoami = {
      replicas       = 2
      user_data      = local.app_bootstrap["whoami"] # rendered shell script
      bootstrap_name = "whoami-whoami-bootstrap"
      tags           = { "traefik.enable" = "true" }
    }
  }
}
```

## Prerequisites

- A Morpheus appliance (**VM Essentials / HVM** or full Morpheus) with an MVM cloud, a group, an Ubuntu-style instance type/layout (cloud-init-enabled image, agent-installable) and a service plan — the plan IS the VM shape.
- The `HPE/hpe` provider authenticated with credentials allowed to create library tasks/workflows and provision instances.

## Notes

- `network` is optional — the layout's default network selection applies when empty (the provider's required `network_interfaces` is passed as `[]`).
- MIGRATED from the community-deprecated `gomorpheus/morpheus` provider (EOL Aug 2026) to the official `HPE/hpe` provider (`~> 1.5`). `plan_provision_type` is now the provision type **code** (`"kvm"`), not the name (`"KVM"`).
