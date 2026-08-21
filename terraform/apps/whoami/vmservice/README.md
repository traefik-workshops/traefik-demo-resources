# apps/whoami/vmservice

Runs Traefik `whoami` on **vSphere VM Service VMs** — the *second* way to provision a vSphere VM. `apps/whoami/vsphere` clones a template into a resource pool with terraform's vsphere provider; this module hands the **vSphere Supervisor's VM Service** (vm-operator) a `VirtualMachine` object inside a **vSphere Namespace**, and the Supervisor builds the VM from a content-library image, a `VirtualMachineClass` and the namespace's storage class and network. The result is an ordinary vCenter VM — VMware Tools, a guest address, tags — so the Hub **vsphere** provider discovers it exactly as it discovers a clone: by the vCenter tags in its `serviceNameCategoryKey` category.

Same workload as every whoami sibling: the shared `whoami/cloud-init` template (Docker + the `whoami` image as a systemd unit), handed to vm-operator as a `rawCloudConfig` bootstrap Secret.

## What is different from the clone sibling

| | `apps/whoami/vsphere` | `apps/whoami/vmservice` |
|---|---|---|
| Who creates the VM | terraform (`vsphere_virtual_machine`) | the Supervisor (vm-operator), from a `VirtualMachine` CRD |
| Where it lives | a resource pool / folder | a vSphere Namespace (its NSX segment, its storage policy, its VM classes) |
| Address | known after apply; optionally **static at plan** via `network_config` | **only after apply** — assigned by the namespace network, read from `status.network.primaryIP4` |
| Tags | ride the VM resource (`tags = […]`) | attached by **govc** after creation, keyed by BIOS UUID |
| Needs on the operator host | `helm` | `kubectl` (Supervisor kubeconfig) + `govc` + `jq` |

The tagging step exists because terraform's `vmware/vsphere` provider has no standalone "attach a tag" resource — tags are an attribute of a VM *it* creates. The VM is found by **BIOS UUID**, never by name: vCenter names are unique per folder only, and a clone-provisioned VM elsewhere may carry the same name.

Because the address is known only after apply, **a caller that needs it at plan time cannot get it from this module.** A child gateway's uplink address, for instance, has to reach the hub through a variable filled between two applies (or the hub must not depend on this module at all). That is the price of letting the Supervisor do the provisioning.

## Example usage

```hcl
module "whoami" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/vmservice?ref=v6.3.1"

  providers = { kubectl = kubectl.supervisor }

  namespace     = "traefik-ns"
  class_name    = "best-effort-small"
  image_name    = "ubuntu-24.04-cloudimg"   # a VirtualMachineImage the namespace can see
  storage_class = "wcp-storage"

  kubeconfig         = "/path/to/supervisor-kubeconfig.yaml"
  kubeconfig_context = "my-supervisor-ctx"

  # Tags are attached through govc: the category and the tags must already exist.
  service_tag_category = vsphere_tag_category.traefik_service.name
  vsphere_server       = "vcenter.lab.example.com"
  vsphere_username     = "administrator@vsphere.local"
  vsphere_password     = var.vsphere_password

  environment = {
    OTEL_SERVICE_NAME           = "whoami-vmsvc"
    OTEL_EXPORTER_OTLP_ENDPOINT = "https://collector.example.com"
  }

  apps = {
    # The app key becomes the VM name prefix (vmsvc-whoami-1, -2): keep it unique in vCenter.
    vmsvc-whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-vmsvc"
      services = ["vmsvcrr", "vmsvcleasttime", "vmsvchrw"]
    }
  }
}
```

## Prerequisites

- A vSphere Namespace with a `VirtualMachineClass`, a storage class and a content library holding a **cloud-init-enabled Ubuntu cloud image** (`kubectl get virtualmachineclass,vmi -n <ns>` lists what the namespace can use).
- A Supervisor kubeconfig for the `kubectl` provider and for the wait script (`kubectl vsphere login` / `vcf context create`, or the Supervisor's `/wcp/login` REST session).
- `govc` and `jq` on the machine running terraform; a vCenter user with the **Assign or Unassign vSphere Tag** privilege.
- The tag category and tags already created (the caller owns them — e.g. `vsphere_tag_category` + `vsphere_tag` in the root).

## Notes

- The Supervisor's own VM naming is visible in vCenter under the namespace's folder; the module never relies on that path.
- `api_version` defaults to `v1alpha3`; a Supervisor serves several versions of `vmoperator.vmware.com` (`kubectl api-resources | grep vmoperator`).
- Destroying the module deletes the `VirtualMachine` (vm-operator deletes the vCenter VM, and the tags go with it) and the bootstrap Secret. The tag *category* and *tags* are the caller's and survive.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.14 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_external"></a> [external](#provider\_external) | >= 2.0 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | >= 1.14 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cloud_init"></a> [cloud\_init](#module\_cloud\_init) | ../cloud-init | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [kubectl_manifest.bootstrap](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.vm](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [null_resource.tags](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [external_external.guest](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_class_name"></a> [class\_name](#input\_class\_name) | VirtualMachineClass the VMs are sized by (e.g. best-effort-small). `kubectl get virtualmachineclass -n <namespace>` lists the ones bound to the namespace. | `string` | n/a | yes |
| <a name="input_image_name"></a> [image\_name](#input\_image\_name) | VirtualMachineImage the VMs boot from — the name `kubectl get vmi -n <namespace>` shows (a content-library OVF item the namespace can see). Must be a cloud-init-enabled Ubuntu CLOUD IMAGE (ubuntu-*-server-cloudimg-amd64.ova) for the rawCloudConfig bootstrap to take. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | vSphere Namespace (a Supervisor namespace) the VirtualMachines are created in. The VirtualMachineClass, the storage class and the image must all be associated with it. | `string` | n/a | yes |
| <a name="input_service_tag_category"></a> [service\_tag\_category](#input\_service\_tag\_category) | vCenter tag CATEGORY the `services` tag names live in — the child gateway's `serviceNameCategoryKey`. The category and its tags must already exist (the caller owns them, e.g. vsphere\_tag\_category + vsphere\_tag); this module only attaches. | `string` | n/a | yes |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Storage class for the VMs' disks (the namespace's storage policy, e.g. wcp-storage). | `string` | n/a | yes |
| <a name="input_vsphere_password"></a> [vsphere\_password](#input\_vsphere\_password) | Password for vsphere\_username. Passed to govc through its environment for the duration of the attach; never written to disk. | `string` | n/a | yes |
| <a name="input_vsphere_server"></a> [vsphere\_server](#input\_vsphere\_server) | vCenter hostname (no scheme) govc attaches the tags against. The VM Service VMs live in this vCenter's inventory like any other VM. | `string` | n/a | yes |
| <a name="input_vsphere_username"></a> [vsphere\_username](#input\_vsphere\_username) | vCenter user govc attaches tags as. Needs the tagging privilege on VMs (vSphere Tagging > Assign or Unassign vSphere Tag). | `string` | n/a | yes |
| <a name="input_allow_unverified_ssl"></a> [allow\_unverified\_ssl](#input\_allow\_unverified\_ssl) | Skip vCenter TLS verification in govc (GOVC\_INSECURE) — self-signed vCenter certs are the lab norm. | `bool` | `true` | no |
| <a name="input_api_version"></a> [api\_version](#input\_api\_version) | vmoperator.vmware.com API version to write the VirtualMachine with. A Supervisor serves several (`kubectl api-resources | grep vmoperator`); v1alpha3 carries the rawCloudConfig bootstrap this module uses and is served by vSphere 8U2+ and 9. | `string` | `"v1alpha3"` | no |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy as VM Service VMs. Each app can have multiple replicas. { name = { replicas, port, name, environment, services } } — `services` is a list of vCenter TAG NAMES (in var.service\_tag\_category) naming the Traefik services these VMs back; each VM is tagged with every one, which is how the Hub vsphere provider discovers them. Optional `environment` (map) is merged over the module-level `environment` into the container. The app KEY becomes the VirtualMachine name prefix (`<key>-<n>`): make it unique in the vCenter inventory. | `any` | `{}` | no |
| <a name="input_common_labels"></a> [common\_labels](#input\_common\_labels) | Kubernetes labels applied to every VirtualMachine and its bootstrap Secret, merged UNDER the module's own `app.kubernetes.io/name`. | `map(string)` | `{}` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_ip_wait_timeout"></a> [ip\_wait\_timeout](#input\_ip\_wait\_timeout) | Seconds to wait for each VM's status.network.primaryIP4 before failing the apply. vm-operator powers the VM on and NSX assigns the address within a minute or two on a healthy Supervisor; a first boot that pulls the image into the namespace can take longer. | `number` | `600` | no |
| <a name="input_kubeconfig"></a> [kubeconfig](#input\_kubeconfig) | Path to the kubeconfig the guest-address wait (local-exec kubectl) should use — the SUPERVISOR kubeconfig, the same one the kubectl provider that creates the VirtualMachine is configured with. Empty = kubectl's ambient config. | `string` | `""` | no |
| <a name="input_kubeconfig_context"></a> [kubeconfig\_context](#input\_kubeconfig\_context) | Context inside `kubeconfig` to use. Set it so the wait targets a named context instead of whatever the machine-global current-context happens to be at that instant (a parallel standup or a mid-apply context switch would otherwise poll the WRONG cluster). | `string` | `""` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Network the VMs' single interface joins (an NSX segment or VDS port group the namespace is entitled to). Empty = the namespace's default network, which is what a plain `VirtualMachine` with no `network` block gets. | `string` | `""` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each VM. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all whoami VMs with their details. private\_ip is status.network.primaryIP4 — the guest address vm-operator reports, the same one VMware Tools reports and the Hub vsphere provider dials. bios\_uuid is what the tag attach located the vCenter object by. |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance keys to their guest IP addresses (known only after apply — vm-operator assigns them). |
| <a name="output_vm_names"></a> [vm\_names](#output\_vm\_names) | VirtualMachine object names, one per replica — also the guests' hostnames and their vCenter inventory names. |
<!-- END_TF_DOCS -->
