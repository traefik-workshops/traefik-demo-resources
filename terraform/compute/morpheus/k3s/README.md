# compute/morpheus/k3s

Single-node **k3s server on an HPE Morpheus instance** — the on-prem stand-in for the managed-k8s modules (EKS/AKS/GKE/OKE/…), and the Morpheus sibling of `compute/vsphere/k3s` / `compute/proxmox/k3s`. Provisions ONE `hpe_morpheus_instance` on an MVM cloud (MVM — the KVM compute type of **HPE VM Essentials / HVM** and full Morpheus; `config_hvm` carries the KVM placement) from an **existing** cloud/group/instance-type/layout/plan (Morpheus owns those concepts; the module looks them up by name) and installs k3s with the bundled Traefik disabled (`traefik/k8s` deploys Traefik Hub instead). k3s's **servicelb (klipper) stays enabled**, so `LoadBalancer` Services get the node IP — the on-prem answer to a cloud LB.

## Bootstrap is a Morpheus provisioning workflow (read this)

The `HPE/hpe` terraform provider exposes **no user-data / cloud-config passthrough** on its instance resource (verified against the v1.5.0 schema — `hpe_morpheus_instance` has no such attribute; neither did gomorpheus's `morpheus_mvm_instance`), so the vSphere-guestinfo / Proxmox-snippet cloud-init delivery is off the table. Instead the module rides Morpheus's **own provisioning pipeline**: the k3s install script becomes an `hpe_morpheus_task_shell_script` (`execute_target = "resource"`, sudo) wrapped in an `hpe_morpheus_workflow_provisioning` (`postProvision` phase) attached to the instance via `task_set_id` — the **Morpheus agent** runs it on the instance as provisioning completes. Honest consequences:

- `config_hvm.no_agent` stays **false** (the provider's own default is `true` — agentless) — the agent executes the bootstrap, and the layout must boot a **cloud-init-enabled Linux image** (that's how Morpheus injects the agent).
- The workflow runs at provision time only; the instance `replace_triggered_by`s the task, so a bootstrap change **recreates the instance** (same first-boot-only story as cloud-init).
- The task/workflow are appliance-level library items named `<vm_name>-k3s-bootstrap` — two stacks reusing one `vm_name` on the same appliance collide.

## Kubeconfig retrieval

k3s mints its admin client certs on the node at install time — there is no API to fetch them. This module **SSHes to the instance** (`ssh_user` + `ssh_private_key`) and reads `/etc/rancher/k3s/k3s.yaml` via an `external` data source, rewriting `127.0.0.1` to the instance IP; the script retries until the bootstrap has finished, so one apply comes up green. Morpheus has no terraform-side key injection on mvm instances either, so **the bootstrap itself authorizes `ssh_public_key`** for `ssh_user` (creating the user if the image doesn't ship it). Needs `ssh`, `jq`, `base64`, `sed` on the machine running terraform, and a network path to the instance.

Auth is **cert-based** (AKS/k3d-style): consume `host` / `cluster_ca_certificate` / `client_certificate` / `client_key` in your `kubernetes`/`helm` providers, or write the `kubeconfig` output to a file.

## Example usage

```hcl
module "k3s" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/morpheus/k3s?ref=v5.2.0"

  cloud              = "hvm-cloud"
  group              = "demo"
  instance_type      = "Ubuntu"
  instance_layout    = "Single KVM VM"
  plan               = "4 CPU, 8GB Memory"
  resource_pool_name = "hvm-cluster-01"

  ssh_private_key = file("~/.ssh/id_ed25519")
  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
}

provider "kubernetes" {
  host                   = module.k3s.host
  cluster_ca_certificate = module.k3s.cluster_ca_certificate
  client_certificate     = module.k3s.client_certificate
  client_key             = module.k3s.client_key
}
```

## Prerequisites

- A Morpheus appliance (**VM Essentials / HVM** or full Morpheus) with an MVM cloud, plus a group, an Ubuntu-style instance type/layout (cloud-init-enabled image, agent-installable) and a service plan — the plan IS the VM shape (no cpu/memory knobs here).
- The `HPE/hpe` provider authenticated with credentials allowed to create library tasks/workflows and provision instances.
- DHCP on the network; outbound internet from the instance (`get.k3s.io` + the k3s artifacts).

## Notes

- Single node by design — a demo hub, not an HA control plane.
- The instance's own IP is already a SAN on the k3s serving cert; `tls_san` only adds extra names.
- `k3s_extra_args` appends raw `k3s server` args for anything else (e.g. `--cluster-cidr`).
- `network` is optional — the layout's default network selection applies when empty (the provider's required `network_interfaces` is passed as `[]`); when set, `network_interface_type_id` is required too (the Morpheus API wants the interface type ID).
- MIGRATED from the community-deprecated `gomorpheus/morpheus` provider (EOL Aug 2026) to the official `HPE/hpe` provider (`~> 1.5`). One functional loss: `hpe_morpheus_instance` has **no `labels` attribute** (v1.5.0), so `morpheus_labels` must stay empty (a validation enforces it) — set Morpheus labels in the appliance instead. `plan_provision_type` is now the provision type **code** (`"kvm"`), not the name (`"KVM"`). State from gomorpheus deployments does not migrate — plan on recreating.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.0 |
| <a name="requirement_hpe"></a> [hpe](#requirement\_hpe) | ~> 1.5 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_external"></a> [external](#provider\_external) | >= 2.0 |
| <a name="provider_hpe"></a> [hpe](#provider\_hpe) | ~> 1.5 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [hpe_morpheus_instance.k3s](https://registry.terraform.io/providers/HPE/hpe/latest/docs/resources/morpheus_instance) | resource |
| [hpe_morpheus_task_shell_script.bootstrap](https://registry.terraform.io/providers/HPE/hpe/latest/docs/resources/morpheus_task_shell_script) | resource |
| [hpe_morpheus_workflow_provisioning.bootstrap](https://registry.terraform.io/providers/HPE/hpe/latest/docs/resources/morpheus_workflow_provisioning) | resource |
| [null_resource.update_kubeconfig](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloud"></a> [cloud](#input\_cloud) | Name of the Morpheus cloud (e.g. the MVM/HVM cloud registered on the appliance) the instance is provisioned into | `string` | n/a | yes |
| <a name="input_group"></a> [group](#input\_group) | Name of the Morpheus group the instance belongs to | `string` | n/a | yes |
| <a name="input_instance_layout"></a> [instance\_layout](#input\_instance\_layout) | Name of the instance layout under instance\_type (e.g. "Single KVM VM") | `string` | n/a | yes |
| <a name="input_plan"></a> [plan](#input\_plan) | Name of the service plan — the plan IS the VM shape on Morpheus (no per-module cpu/memory knobs), so pick one that fits a demo hub (e.g. "4 CPU, 8GB Memory") | `string` | n/a | yes |
| <a name="input_resource_pool_name"></a> [resource\_pool\_name](#input\_resource\_pool\_name) | Name of the resource pool (the MVM/HVM cluster) to provision the instance to | `string` | n/a | yes |
| <a name="input_ssh_private_key"></a> [ssh\_private\_key](#input\_ssh\_private\_key) | PEM private key the kubeconfig fetch SSHes with. Its public half must be accepted by ssh\_user — pass ssh\_public\_key (the bootstrap authorizes it) or bake it into the virtual image. | `string` | n/a | yes |
| <a name="input_computed_placement_ids"></a> [computed\_placement\_ids](#input\_computed\_placement\_ids) | Set true when instance\_type\_id / instance\_layout\_id / resource\_pool\_id are supplied from APPLY-TIME values (a data source or resource output, e.g. the demo's data.external.box\_state). Those go unknown at destroy, and `count = var.<id> == null ? 1 : 0` then fails with "Invalid count argument". With this true the name-lookup count short-circuits to 0 on a known value (`true || unknown` = true in HCL), so destroy plans cleanly. Leave false when the ids are static literals or you resolve by name. | `bool` | `false` | no |
| <a name="input_enable_provisioning_workflow"></a> [enable\_provisioning\_workflow](#input\_enable\_provisioning\_workflow) | Wrap the bootstrap task in a Morpheus PROVISIONING WORKFLOW (a task-set) and attach it to each instance via task\_set\_id — the native path, which runs the bootstrap at postProvision. Requires features.workflows: HPE VM Essentials does NOT have it (POST /api/task-sets -> 403 "Feature Not Included for the Applied License", and the 403 fires before body validation). Set FALSE on VME and execute the task DIRECTLY instead — POST /api/tasks/{id}/execute is ungated (it answers 404 for a bogus id, not 403), and the task resource itself is fine (features.tasks=true). When false the CALLER owns triggering the bootstrap after provisioning; the module exposes bootstrap\_task\_ids for exactly that. | `bool` | `true` | no |
| <a name="input_instance_layout_id"></a> [instance\_layout\_id](#input\_instance\_layout\_id) | Literal layout id, bypassing the name lookup. REQUIRED on HPE VM Essentials (see instance\_type\_id). Also disambiguates: "Single KVM VM" is NOT unique — Ubuntu carries several. null = resolve by name. | `number` | `null` | no |
| <a name="input_instance_layout_version"></a> [instance\_layout\_version](#input\_instance\_layout\_version) | Version of the instance layout (e.g. "24.04") — disambiguates layouts sharing a name. Empty = match by name alone. | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Name of the Morpheus instance type to provision from (e.g. "Ubuntu"). Must be an instance type whose layout boots a cloud-init-enabled Linux image — the Morpheus agent (installed via cloud-init) is what runs the k3s bootstrap. | `string` | `"Ubuntu"` | no |
| <a name="input_instance_type_id"></a> [instance\_type\_id](#input\_instance\_type\_id) | Literal instance-type id, bypassing the name lookup. REQUIRED on HPE VM Essentials: the hpe\_morpheus\_instance\_type data source calls /api/library/instance-types, which 403s (templates=false) at PLAN time. null = resolve by name (full Morpheus, where the Library is licensed). | `number` | `null` | no |
| <a name="input_k3s_channel"></a> [k3s\_channel](#input\_k3s\_channel) | k3s release channel for the install script (stable, latest, or a minor like v1.31) | `string` | `"stable"` | no |
| <a name="input_k3s_extra_args"></a> [k3s\_extra\_args](#input\_k3s\_extra\_args) | Extra `k3s server` arguments appended to the install. The module always sets --disable traefik (the traefik/k8s module deploys Hub instead) and --write-kubeconfig-mode 644 (the SSH kubeconfig fetch reads it without sudo); servicelb stays enabled so LoadBalancer Services get the node IP. | `list(string)` | `[]` | no |
| <a name="input_kubeconfig_timeout"></a> [kubeconfig\_timeout](#input\_kubeconfig\_timeout) | Seconds the kubeconfig fetch waits for provisioning + the k3s bootstrap to finish | `number` | `600` | no |
| <a name="input_morpheus_labels"></a> [morpheus\_labels](#input\_morpheus\_labels) | MUST STAY EMPTY: the HPE/hpe provider's hpe\_morpheus\_instance exposes NO labels attribute (checked at v1.5.0; gomorpheus's morpheus\_mvm\_instance did), so Morpheus labels can't be applied from terraform anymore. The variable is kept (and validated empty) so existing callers passing [] keep working; set labels in the appliance instead. | `list(string)` | `[]` | no |
| <a name="input_network"></a> [network](#input\_network) | Name of the Morpheus network the instance NIC joins (DHCP is assumed). Empty = the layout's default network selection; set it (plus network\_interface\_type\_id) when the layout doesn't default one. | `string` | `""` | no |
| <a name="input_network_interface_type_id"></a> [network\_interface\_type\_id](#input\_network\_interface\_type\_id) | Morpheus network interface TYPE ID for the NIC (required when network is set; the KVM virtio type on MVM clouds — look it up in the appliance) | `number` | `null` | no |
| <a name="input_plan_provision_type"></a> [plan\_provision\_type](#input\_plan\_provision\_type) | Provision type CODE the plan is looked up under (the hpe\_morpheus\_service\_plan data source filters by provision\_type\_code; "kvm" for MVM / HPE VM Essentials clouds — the gomorpheus-era value here was the NAME "KVM"). Empty = match the plan by name alone. | `string` | `"kvm"` | no |
| <a name="input_resource_pool_id"></a> [resource\_pool\_id](#input\_resource\_pool\_id) | Literal resource-pool id, bypassing the name lookup. REQUIRED on HPE VM Essentials: it has no ResourcePool records (/api/resource-pools -> total=0) — the HVM cluster is a synthetic "pool-<clusterId>" served only by the zonePools option source, so the data source fails at PLAN time with "found 0 resourcePools". null = resolve by name (full Morpheus). | `string` | `null` | no |
| <a name="input_root_volume"></a> [root\_volume](#input\_root\_volume) | Optional explicit root volume {size (GB), datastore\_id, storage\_type, name}. null = the layout/plan defaults. | <pre>object({<br/>    size         = number<br/>    datastore_id = number<br/>    storage_type = optional(number, 1)<br/>    name         = optional(string, "root")<br/>  })</pre> | `null` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key the bootstrap task authorizes for ssh\_user. Empty = the image (or the Morpheus provisioning user's key pair) must already accept ssh\_private\_key. | `string` | `""` | no |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | SSH user the kubeconfig fetch logs in as. The bootstrap creates it (and authorizes ssh\_public\_key) when the image doesn't ship it. | `string` | `"ubuntu"` | no |
| <a name="input_tls_san"></a> [tls\_san](#input\_tls\_san) | Extra Subject Alternative Name for the k3s serving cert (--tls-san). The node's own IP is a SAN by default, so this is only needed to reach the API by another name (a DNS alias, a VIP). | `string` | `""` | no |
| <a name="input_update_kubeconfig"></a> [update\_kubeconfig](#input\_update\_kubeconfig) | Merge this cluster into the ambient kubeconfig (~/.kube/config, context k3s-<vm\_name>) after creation and switch the current context to it — the on-prem analogue of the cloud modules' `update_kubeconfig`. | `bool` | `true` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Name for the k3s instance (also its hostname, and the prefix of the bootstrap task/workflow names — unique per appliance) | `string` | `"k3s"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bootstrap_task_ids"></a> [bootstrap\_task\_ids](#output\_bootstrap\_task\_ids) | Bootstrap shell-script task ids, by app. Only useful when enable\_provisioning\_workflow=false: the caller executes these itself via POST /api/tasks/{id}/execute with {"job":{"targetType":"instance","instances":[<id>]}} — the ungated path on HPE VM Essentials. |
| <a name="output_client_certificate"></a> [client\_certificate](#output\_client\_certificate) | Admin client certificate (PEM) — k3s auth is cert-based, AKS/k3d-style |
| <a name="output_client_key"></a> [client\_key](#output\_client\_key) | Admin client key (PEM) |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Cluster CA certificate (PEM) |
| <a name="output_host"></a> [host](#output\_host) | Kubernetes API endpoint (https://<instance-ip>:6443) |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig (server rewritten from 127.0.0.1 to the instance IP) |
| <a name="output_node_ip"></a> [node\_ip](#output\_node\_ip) | The instance's primary connection IP (connection\_info[0]) — also where klipper (k3s servicelb) publishes LoadBalancer Services, so point demo DNS / /etc/hosts entries here |
| <a name="output_vm_id"></a> [vm\_id](#output\_vm\_id) | Morpheus instance ID of the k3s instance |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | Name of the k3s instance |
<!-- END_TF_DOCS -->