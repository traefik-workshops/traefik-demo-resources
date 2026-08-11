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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_hpe"></a> [hpe](#requirement\_hpe) | ~> 1.5 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_hpe"></a> [hpe](#provider\_hpe) | ~> 1.5 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [hpe_morpheus_instance.this](https://registry.terraform.io/providers/HPE/hpe/latest/docs/resources/morpheus_instance) | resource |
| [hpe_morpheus_task_shell_script.bootstrap](https://registry.terraform.io/providers/HPE/hpe/latest/docs/resources/morpheus_task_shell_script) | resource |
| [hpe_morpheus_workflow_provisioning.bootstrap](https://registry.terraform.io/providers/HPE/hpe/latest/docs/resources/morpheus_workflow_provisioning) | resource |
| [hpe_morpheus_cloud.this](https://registry.terraform.io/providers/HPE/hpe/latest/docs/data-sources/morpheus_cloud) | data source |
| [hpe_morpheus_group.this](https://registry.terraform.io/providers/HPE/hpe/latest/docs/data-sources/morpheus_group) | data source |
| [hpe_morpheus_instance_type.this](https://registry.terraform.io/providers/HPE/hpe/latest/docs/data-sources/morpheus_instance_type) | data source |
| [hpe_morpheus_instance_type_layout.this](https://registry.terraform.io/providers/HPE/hpe/latest/docs/data-sources/morpheus_instance_type_layout) | data source |
| [hpe_morpheus_network.this](https://registry.terraform.io/providers/HPE/hpe/latest/docs/data-sources/morpheus_network) | data source |
| [hpe_morpheus_resource_pool.this](https://registry.terraform.io/providers/HPE/hpe/latest/docs/data-sources/morpheus_resource_pool) | data source |
| [hpe_morpheus_service_plan.this](https://registry.terraform.io/providers/HPE/hpe/latest/docs/data-sources/morpheus_service_plan) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of apps to provision as hpe\_morpheus\_instances. Key = the instance-name prefix, so each replica is "<key>-<replica>" (1-based), mirroring the ec2/azure-vm/vsphere sibling scheme. Per app: `replicas` (default 1); `user_data` — the ALREADY-RENDERED bootstrap shell script, delivered verbatim as the Morpheus task's script\_content (OPAQUE to this module; the caller renders its own cloud-init and converts it to a shell script); `bootstrap_name` — the exact appliance-level library-item name for the task + provisioning workflow (unique per appliance); `tags` — dotted Traefik labels applied 1:1 as instance name/value tags (the Hub morpheus provider reads every traefik.* tag), {} => no tags (null); `private_ips` — fixed static IP per replica index (private\_ips[replica] pins the NIC to ip\_mode=static/ip\_address; [] or a short list => DHCP / the layout's IP pool for the unpinned replicas). | <pre>map(object({<br/>    replicas       = optional(number, 1)<br/>    user_data      = string<br/>    bootstrap_name = string<br/>    tags           = optional(map(string), {})<br/>    private_ips    = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_cloud"></a> [cloud](#input\_cloud) | Name of the Morpheus cloud (e.g. the MVM/HVM cloud registered on the appliance) the instances are provisioned into | `string` | n/a | yes |
| <a name="input_group"></a> [group](#input\_group) | Name of the Morpheus group the instances belong to | `string` | n/a | yes |
| <a name="input_instance_layout"></a> [instance\_layout](#input\_instance\_layout) | Name of the instance layout under instance\_type (e.g. "Single KVM VM") | `string` | n/a | yes |
| <a name="input_plan"></a> [plan](#input\_plan) | Name of the service plan — the plan IS the VM shape on Morpheus (no cpu/memory knobs here); pick one that fits the workload | `string` | n/a | yes |
| <a name="input_resource_pool_name"></a> [resource\_pool\_name](#input\_resource\_pool\_name) | Name of the resource pool (the MVM/HVM cluster) to provision the instances to | `string` | n/a | yes |
| <a name="input_computed_placement_ids"></a> [computed\_placement\_ids](#input\_computed\_placement\_ids) | Set true when instance\_type\_id / instance\_layout\_id / resource\_pool\_id are supplied from APPLY-TIME values (a data source or resource output, e.g. the demo's data.external.box\_state). Those go unknown at destroy, and `count = var.<id> == null ? 1 : 0` then fails with "Invalid count argument". With this true the name-lookup count short-circuits to 0 on a known value (`true || unknown` = true in HCL), so destroy plans cleanly. Leave false when the ids are static literals or you resolve by name. | `bool` | `false` | no |
| <a name="input_enable_provisioning_workflow"></a> [enable\_provisioning\_workflow](#input\_enable\_provisioning\_workflow) | Wrap the bootstrap task in a Morpheus PROVISIONING WORKFLOW (a task-set) and attach it to each instance via task\_set\_id — the native path, which runs the bootstrap at postProvision. Requires features.workflows: HPE VM Essentials does NOT have it (POST /api/task-sets -> 403 "Feature Not Included for the Applied License", and the 403 fires before body validation). Set FALSE on VME and execute the task DIRECTLY instead — POST /api/tasks/{id}/execute is ungated (it answers 404 for a bogus id, not 403), and the task resource itself is fine (features.tasks=true). When false the CALLER owns triggering the bootstrap after provisioning; the module exposes bootstrap\_task\_ids for exactly that. | `bool` | `true` | no |
| <a name="input_instance_layout_id"></a> [instance\_layout\_id](#input\_instance\_layout\_id) | Literal layout id, bypassing the name lookup. REQUIRED on HPE VM Essentials (see instance\_type\_id). Also disambiguates: "Single KVM VM" is NOT unique — Ubuntu carries several. null = resolve by name. | `number` | `null` | no |
| <a name="input_instance_layout_version"></a> [instance\_layout\_version](#input\_instance\_layout\_version) | Version of the instance layout (e.g. "24.04") — disambiguates layouts sharing a name. Empty = match by name alone. | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Name of the Morpheus instance type to provision from (e.g. "Ubuntu"). Must boot a cloud-init-enabled Linux image — the Morpheus agent (installed via cloud-init) runs the bootstrap. | `string` | `"Ubuntu"` | no |
| <a name="input_instance_type_id"></a> [instance\_type\_id](#input\_instance\_type\_id) | Literal instance-type id, bypassing the name lookup. REQUIRED on HPE VM Essentials: the hpe\_morpheus\_instance\_type data source calls /api/library/instance-types, which 403s (templates=false) at PLAN time. null = resolve by name (full Morpheus, where the Library is licensed). | `number` | `null` | no |
| <a name="input_network"></a> [network](#input\_network) | Name of the Morpheus network the instance NICs join (DHCP is assumed unless a per-app private\_ips pin is set). Empty = the layout's default network selection. | `string` | `""` | no |
| <a name="input_network_interface_type_id"></a> [network\_interface\_type\_id](#input\_network\_interface\_type\_id) | Morpheus network interface TYPE ID for the NICs (optional; VME does not require one) | `number` | `null` | no |
| <a name="input_plan_provision_type"></a> [plan\_provision\_type](#input\_plan\_provision\_type) | Provision type CODE the plan is looked up under (the hpe\_morpheus\_service\_plan data source filters by provision\_type\_code; "kvm" for MVM / HPE VM Essentials clouds — the gomorpheus-era value here was the NAME "KVM"). Empty = match the plan by name alone. | `string` | `"kvm"` | no |
| <a name="input_resource_pool_id"></a> [resource\_pool\_id](#input\_resource\_pool\_id) | Literal resource-pool id, bypassing the name lookup. REQUIRED on HPE VM Essentials: it has no ResourcePool records (/api/resource-pools -> total=0) — the HVM cluster is a synthetic "pool-<clusterId>" served only by the zonePools option source, so the data source fails at PLAN time with "found 0 resourcePools". null = resolve by name (full Morpheus). | `string` | `null` | no |
| <a name="input_root_volume"></a> [root\_volume](#input\_root\_volume) | Optional explicit root volume {size (GB), datastore\_id, storage\_type, name}. null = the layout/plan defaults. | <pre>object({<br/>    size         = number<br/>    datastore_id = number<br/>    storage_type = optional(number, 1)<br/>    name         = optional(string, "root")<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bootstrap_task_ids"></a> [bootstrap\_task\_ids](#output\_bootstrap\_task\_ids) | Bootstrap shell-script task ids, by app key. Only useful when enable\_provisioning\_workflow=false: the caller executes these itself via POST /api/tasks/{id}/execute with {"job":{"targetType":"instance","instances":[<id>]}} — the ungated path on HPE VM Essentials. |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all instances keyed by "<app>-<replica>" with their details. private\_ip and public\_ip are the SAME primary connection address (connection\_info[0]) — on-prem Morpheus instances have one primary IP and no cloud public-IP concept (the provider's private/public ipModes both resolve to it). |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance keys to their primary IP addresses (the parent dials this address) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance keys to their primary IP addresses — identical to private\_ips (no public-IP concept on-prem; kept for sibling-parity with compute/aws/ec2) |
<!-- END_TF_DOCS -->
