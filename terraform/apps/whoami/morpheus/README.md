# apps/whoami/morpheus

Provisions one or more Traefik `whoami` instances on **HPE Morpheus** (MVM — the KVM compute type of **VM Essentials / HVM** and full Morpheus) — the on-prem sibling of `apps/whoami/ec2` / `apps/whoami/azure-vm` / `apps/whoami/vsphere`, reusing the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `ghcr.io/zalbiraw/whoami`). Each replica is one small `hpe_morpheus_instance` (on an MVM cloud; `config_hvm` carries the KVM placement) provisioned from an existing instance type/layout/plan.

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
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/morpheus?ref=v5.1.0"

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

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |

## Providers

No providers.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloud"></a> [cloud](#input\_cloud) | Name of the Morpheus cloud (e.g. the MVM/HVM cloud registered on the appliance) the instances are provisioned into | `string` | n/a | yes |
| <a name="input_group"></a> [group](#input\_group) | Name of the Morpheus group the instances belong to | `string` | n/a | yes |
| <a name="input_instance_layout"></a> [instance\_layout](#input\_instance\_layout) | Name of the instance layout under instance\_type (e.g. "Single KVM VM") | `string` | n/a | yes |
| <a name="input_plan"></a> [plan](#input\_plan) | Name of the service plan — the plan IS the VM shape on Morpheus (no per-module cpu/memory knobs); a small one fits whoami (e.g. "1 CPU, 2GB Memory") | `string` | n/a | yes |
| <a name="input_resource_pool_name"></a> [resource\_pool\_name](#input\_resource\_pool\_name) | Name of the resource pool (the MVM/HVM cluster) to provision the instances to | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to Morpheus instances. Each app can have multiple replicas. Same shape as apps/whoami/vsphere: { name = { replicas, port, name, environment, traefik\_labels } } — `traefik_labels` (dotted Traefik label -> value) lands 1:1 as instance TAGS (the Hub morpheus provider reads every traefik.* tag); optional `environment` (map) is merged over the module-level `environment` into the container. The gomorpheus-era per-app `labels` entry (Morpheus LABELS) is NO LONGER APPLIED — hpe\_morpheus\_instance (HPE/hpe v1.5.0) has no labels attribute — and a non-empty value now fails the validation below; set labels via the appliance instead. | `any` | `{}` | no |
| <a name="input_computed_placement_ids"></a> [computed\_placement\_ids](#input\_computed\_placement\_ids) | Passthrough to compute/morpheus/vm: set true when instance\_type\_id / instance\_layout\_id / resource\_pool\_id are supplied from apply-time values (they go unknown at destroy and break the name-lookup count with Invalid count argument). See that module's variable of the same name. | `bool` | `false` | no |
| <a name="input_enable_provisioning_workflow"></a> [enable\_provisioning\_workflow](#input\_enable\_provisioning\_workflow) | Wrap the bootstrap task in a Morpheus PROVISIONING WORKFLOW (a task-set) and attach it to each instance via task\_set\_id — the native path, which runs the bootstrap at postProvision. Requires features.workflows: HPE VM Essentials does NOT have it (POST /api/task-sets -> 403 "Feature Not Included for the Applied License", and the 403 fires before body validation). Set FALSE on VME and execute the task DIRECTLY instead — POST /api/tasks/{id}/execute is ungated (it answers 404 for a bogus id, not 403), and the task resource itself is fine (features.tasks=true). When false the CALLER owns triggering the bootstrap after provisioning; the module exposes bootstrap\_task\_ids for exactly that. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_instance_layout_id"></a> [instance\_layout\_id](#input\_instance\_layout\_id) | Literal layout id, bypassing the name lookup. REQUIRED on HPE VM Essentials (see instance\_type\_id). Also disambiguates: "Single KVM VM" is NOT unique — Ubuntu carries several. null = resolve by name. | `number` | `null` | no |
| <a name="input_instance_layout_version"></a> [instance\_layout\_version](#input\_instance\_layout\_version) | Version of the instance layout (e.g. "24.04") — disambiguates layouts sharing a name. Empty = match by name alone. | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Name of the Morpheus instance type to provision from (e.g. "Ubuntu"). Must boot a cloud-init-enabled Linux image — the Morpheus agent (installed via cloud-init) runs the whoami bootstrap. | `string` | `"Ubuntu"` | no |
| <a name="input_instance_type_id"></a> [instance\_type\_id](#input\_instance\_type\_id) | Literal instance-type id, bypassing the name lookup. REQUIRED on HPE VM Essentials: the hpe\_morpheus\_instance\_type data source calls /api/library/instance-types, which 403s (templates=false) at PLAN time. null = resolve by name (full Morpheus, where the Library is licensed). | `number` | `null` | no |
| <a name="input_morpheus_labels"></a> [morpheus\_labels](#input\_morpheus\_labels) | MUST STAY EMPTY: the HPE/hpe provider's hpe\_morpheus\_instance exposes NO labels attribute (checked at v1.5.0; gomorpheus's morpheus\_mvm\_instance did), so Morpheus labels can't be applied from terraform anymore. The variable is kept (and validated empty) so existing callers passing [] keep working; set labels in the appliance instead. | `list(string)` | `[]` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for the per-app bootstrap task/workflow names (appliance-level library items — two stacks sharing a prefix and app names on one appliance collide) | `string` | `"whoami"` | no |
| <a name="input_network"></a> [network](#input\_network) | Name of the Morpheus network the instance NICs join (DHCP is assumed; the Traefik child dials each instance's primary IP). Empty = the layout's default network selection. | `string` | `""` | no |
| <a name="input_network_interface_type_id"></a> [network\_interface\_type\_id](#input\_network\_interface\_type\_id) | Morpheus network interface TYPE ID for the NICs (required when network is set) | `number` | `null` | no |
| <a name="input_plan_provision_type"></a> [plan\_provision\_type](#input\_plan\_provision\_type) | Provision type CODE the plan is looked up under (the hpe\_morpheus\_service\_plan data source filters by provision\_type\_code; "kvm" for MVM / HPE VM Essentials clouds — the gomorpheus-era value here was the NAME "KVM"). Empty = match the plan by name alone. | `string` | `"kvm"` | no |
| <a name="input_resource_pool_id"></a> [resource\_pool\_id](#input\_resource\_pool\_id) | Literal resource-pool id, bypassing the name lookup. REQUIRED on HPE VM Essentials: it has no ResourcePool records (/api/resource-pools -> total=0) — the HVM cluster is a synthetic "pool-<clusterId>" served only by the zonePools option source, so the data source fails at PLAN time with "found 0 resourcePools". null = resolve by name (full Morpheus). | `string` | `null` | no |
| <a name="input_root_volume"></a> [root\_volume](#input\_root\_volume) | Optional explicit root volume {size (GB), datastore\_id, storage\_type, name}. null = the layout/plan defaults. | <pre>object({<br/>    size         = number<br/>    datastore_id = number<br/>    storage_type = optional(number, 1)<br/>    name         = optional(string, "root")<br/>  })</pre> | `null` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each instance. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/zalbiraw/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bootstrap_task_ids"></a> [bootstrap\_task\_ids](#output\_bootstrap\_task\_ids) | Bootstrap shell-script task ids, by app. Only useful when enable\_provisioning\_workflow=false: the caller executes these itself via POST /api/tasks/{id}/execute with {"job":{"targetType":"instance","instances":[<id>]}} — the ungated path on HPE VM Essentials. |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server instances with their details (private\_ip is the primary connection IP Morpheus reports, connection\_info[0] — on-prem there's no private/public distinction, the provider's ipModes resolve to the same address) |
<!-- END_TF_DOCS -->