# compute/proxmox/k3s

Single-node **k3s server on a Proxmox VE VM** — the on-prem stand-in for the managed-k8s modules (EKS/AKS/GKE/OKE/…), and the Proxmox sibling of `compute/vsphere/k3s`. Clones a user-provided **cloud-init-enabled Ubuntu cloud-image template** and installs k3s at first boot with the bundled Traefik disabled (`traefik/k8s` deploys Traefik Hub instead). k3s's **servicelb (klipper) stays enabled**, so `LoadBalancer` Services get the node IP — the on-prem answer to a cloud LB.

## Cloud-init on Proxmox is a snippet file

Unlike vSphere's inline `guestinfo` blob, Proxmox delivers arbitrary user-data as a **snippet file on a datastore**: the module uploads the cloud-config with `proxmox_virtual_environment_file` (`content_type = "snippets"`) and points the VM's `initialization.user_data_file_id` at it. Two honest consequences:

- **Snippet uploads go over SSH/SFTP** (the PVE API has no snippet upload), so the `bpg/proxmox` provider needs its `ssh {}` block configured (username + key/agent for the node).
- The **snippet datastore must allow the Snippets content type** (`snippet_datastore_id`, default `local`).

The snippet's file name carries a content hash, and the VM `replace_triggered_by`s it — a user-data change recreates the VM (cloud-init only runs on first boot).

## Kubeconfig retrieval (read this)

k3s mints its admin client certs on the node at install time — there is no API to fetch them. This module **SSHes to the VM** (`ssh_user` + `ssh_private_key`) and reads `/etc/rancher/k3s/k3s.yaml` via an `external` data source, rewriting `127.0.0.1` to the VM's IP. The script retries until k3s finishes installing, so one apply comes up green. Honest prerequisites:

- `ssh`, `jq`, `base64`, `sed` on the machine running terraform,
- the template's default user must accept `ssh_private_key` — bake the public key into the template **or** pass `ssh_public_key` (cloud-init authorizes it at first boot).

Auth is **cert-based** (AKS/k3d-style): consume `host` / `cluster_ca_certificate` / `client_certificate` / `client_key` in your `kubernetes`/`helm` providers, or write the `kubeconfig` output to a file.

## Example usage

```hcl
module "k3s" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/proxmox/k3s?ref=v8.1.0"

  node_name     = "pve"
  datastore_id  = "local-lvm"
  template_name = "ubuntu-24.04-cloudimg" # or template_vm_id = 9000

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

- The `bpg/proxmox` provider configured with an API token allowed to clone VMs **plus** its `ssh {}` block (snippet upload).
- A **cloud-init-enabled Ubuntu cloud-image template** — import a cloud image (e.g. `noble-server-cloudimg-amd64.img`), attach a cloud-init drive, convert to template. Ideally bake `qemu-guest-agent` in (`virt-customize -a <img> --install qemu-guest-agent`); this module also installs it via cloud-init as belt-and-braces, but the agent is what reports the guest IP, so a template without it and without egress never surfaces an address.
- DHCP on the bridge (the module passes no static network config); outbound internet from the VM (`get.k3s.io` + the k3s artifacts).

## Notes

- Single node by design — a demo hub, not an HA control plane.
- The VM's own IP is already a SAN on the k3s serving cert; `tls_san` only adds extra names.
- `k3s_extra_args` appends raw `k3s server` args for anything else (e.g. `--cluster-cidr`).
- `cpu_type` defaults to `host` (fastest, lab-friendly); pick a named model when live migration matters.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | >= 0.60.0, < 1.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_external"></a> [external](#provider\_external) | >= 2.0 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | >= 0.60.0, < 1.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [null_resource.update_kubeconfig](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [proxmox_virtual_environment_file.user_data](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_vm.k3s](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |
| [external_external.kubeconfig](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |
| [proxmox_virtual_environment_vms.template](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/data-sources/virtual_environment_vms) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Datastore backing the VM's disk and cloud-init drive (e.g. local-lvm). Must be the datastore the template's disk lives on, or the clone's disk is moved there. | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Name of the Proxmox VE node the VM is created on | `string` | n/a | yes |
| <a name="input_ssh_private_key"></a> [ssh\_private\_key](#input\_ssh\_private\_key) | PEM private key the kubeconfig fetch SSHes with. Its public half must be accepted by ssh\_user — bake it into the template or pass ssh\_public\_key. | `string` | n/a | yes |
| <a name="input_bridge"></a> [bridge](#input\_bridge) | Name of the Linux bridge the VM's NIC joins (DHCP is assumed) | `string` | `"vmbr0"` | no |
| <a name="input_cpu_type"></a> [cpu\_type](#input\_cpu\_type) | QEMU CPU type. `host` passes the node's CPU through (fastest, lab-friendly); pick a named model (e.g. x86-64-v2-AES) when live migration matters. | `string` | `"host"` | no |
| <a name="input_disk_interface"></a> [disk\_interface](#input\_disk\_interface) | Interface of the template's disk to resize (the standard cloud-image import recipe attaches it as scsi0) | `string` | `"scsi0"` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Disk size in GB. Must be at least the template's disk (Proxmox can't shrink on clone). | `number` | `40` | no |
| <a name="input_k3s_channel"></a> [k3s\_channel](#input\_k3s\_channel) | k3s release channel for the install script (stable, latest, or a minor like v1.31) | `string` | `"stable"` | no |
| <a name="input_k3s_extra_args"></a> [k3s\_extra\_args](#input\_k3s\_extra\_args) | Extra `k3s server` arguments appended to the install. The module always sets --disable traefik (the traefik/k8s module deploys Hub instead) and --write-kubeconfig-mode 644 (the SSH kubeconfig fetch reads it without sudo); servicelb stays enabled so LoadBalancer Services get the node IP. | `list(string)` | `[]` | no |
| <a name="input_kubeconfig_timeout"></a> [kubeconfig\_timeout](#input\_kubeconfig\_timeout) | Seconds the kubeconfig fetch waits for k3s to finish installing on first boot | `number` | `300` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB | `number` | `8192` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count. The default fits a demo hub (Traefik Hub + Keycloak + a Grafana stack). | `number` | `4` | no |
| <a name="input_snippet_datastore_id"></a> [snippet\_datastore\_id](#input\_snippet\_datastore\_id) | Datastore the cloud-init user-data snippet is uploaded to. Must have the Snippets content type enabled (the stock `local` does after enabling it in Datacenter > Storage). | `string` | `"local"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key cloud-init authorizes for the template's default user at first boot. Empty = the template must already accept ssh\_private\_key. | `string` | `""` | no |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | SSH user the kubeconfig fetch logs in as (the Ubuntu cloud image default user is `ubuntu`) | `string` | `"ubuntu"` | no |
| <a name="input_template_name"></a> [template\_name](#input\_template\_name) | Name of the template to clone (resolved to a VMID on the node). Takes precedence over template\_vm\_id. | `string` | `""` | no |
| <a name="input_template_vm_id"></a> [template\_vm\_id](#input\_template\_vm\_id) | VMID of the template to clone. Provide this OR template\_name. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (imported cloud image + cloud-init drive) — a plain installer-built template ignores the user-data and nothing boots k3s. | `number` | `0` | no |
| <a name="input_tls_san"></a> [tls\_san](#input\_tls\_san) | Extra Subject Alternative Name for the k3s serving cert (--tls-san). The node's own IP is a SAN by default, so this is only needed to reach the API by another name (a DNS alias, a VIP). | `string` | `""` | no |
| <a name="input_update_kubeconfig"></a> [update\_kubeconfig](#input\_update\_kubeconfig) | Merge this cluster into the ambient kubeconfig (~/.kube/config, context k3s-<vm\_name>) after creation and switch the current context to it — the on-prem analogue of the cloud modules' `update_kubeconfig`. | `bool` | `true` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Name for the k3s VM (also its hostname via the PVE-generated cloud-init meta-data) | `string` | `"k3s"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_client_certificate"></a> [client\_certificate](#output\_client\_certificate) | Admin client certificate (PEM) — k3s auth is cert-based, AKS/k3d-style |
| <a name="output_client_key"></a> [client\_key](#output\_client\_key) | Admin client key (PEM) |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Cluster CA certificate (PEM) |
| <a name="output_host"></a> [host](#output\_host) | Kubernetes API endpoint (https://<vm-ip>:6443) |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig (server rewritten from 127.0.0.1 to the VM IP) |
| <a name="output_node_ip"></a> [node\_ip](#output\_node\_ip) | The VM's guest IP (QEMU-agent-reported) — also where klipper (k3s servicelb) publishes LoadBalancer Services, so point demo DNS / /etc/hosts entries here |
| <a name="output_vm_id"></a> [vm\_id](#output\_vm\_id) | Proxmox VMID of the k3s VM |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | Name of the k3s VM |
<!-- END_TF_DOCS -->