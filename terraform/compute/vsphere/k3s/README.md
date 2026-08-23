# compute/vsphere/k3s

Single-node **k3s server on a vSphere VM** — the on-prem stand-in for the managed-k8s modules (EKS/AKS/GKE/OKE/…). Clones a user-provided **cloud-init-enabled Ubuntu cloud-image template** and installs k3s at first boot with the bundled Traefik disabled (`traefik/k8s` deploys Traefik Hub instead). k3s's **servicelb (klipper) stays enabled**, so `LoadBalancer` Services get the node IP — the on-prem answer to a cloud LB.

## Kubeconfig retrieval (read this)

k3s mints its admin client certs on the node at install time — there is no API to fetch them. This module **SSHes to the VM** (`ssh_user` + `ssh_private_key`) and reads `/etc/rancher/k3s/k3s.yaml` via an `external` data source, rewriting `127.0.0.1` to the VM's IP. The script retries until k3s finishes installing, so one apply comes up green. Honest prerequisites:

- `ssh`, `jq`, `base64`, `sed` on the machine running terraform,
- the template's default user must accept `ssh_private_key` — bake the public key into the template **or** pass `ssh_public_key` (cloud-init authorizes it at first boot).

Auth is **cert-based** (AKS/k3d-style): consume `host` / `cluster_ca_certificate` / `client_certificate` / `client_key` in your `kubernetes`/`helm` providers, or write the `kubeconfig` output to a file.

## Example usage

```hcl
module "k3s" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/vsphere/k3s?ref=v7.0.0"

  datacenter = "dc-01"
  datastore  = "datastore-01"
  cluster    = "cluster-01" # or resource_pool = "cluster-01/Resources/demo"
  network    = "VM Network"
  template   = "ubuntu-24.04-cloudimg" # cloud-init-enabled Ubuntu cloud image

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

- vCenter reachable from the machine running terraform; the `vsphere` provider configured with credentials allowed to clone VMs.
- A **cloud-init-enabled Ubuntu cloud-image template** (e.g. import `ubuntu-24.04-server-cloudimg-amd64.ova` and convert to template). Cloud-init on those images reads the VMware `guestinfo` datasource — a plain installer-built template ignores the userdata and nothing boots k3s. `open-vm-tools` (included in the cloud images) must run, or vSphere never reports the guest IP.
- DHCP on the target network (the module passes no static network config).
- Outbound internet from the VM (`get.k3s.io` + the k3s artifacts).

## Notes

- Single node by design — a demo hub, not an HA control plane.
- The VM's own IP is already a SAN on the k3s serving cert; `tls_san` only adds extra names.
- `k3s_extra_args` appends raw `k3s server` args for anything else (e.g. `--cluster-cidr`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |
| <a name="requirement_vsphere"></a> [vsphere](#requirement\_vsphere) | ~> 2.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_external"></a> [external](#provider\_external) | >= 2.0 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |
| <a name="provider_vsphere"></a> [vsphere](#provider\_vsphere) | ~> 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [null_resource.update_kubeconfig](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [vsphere_virtual_machine.k3s](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/resources/virtual_machine) | resource |
| [external_external.kubeconfig](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |
| [vsphere_compute_cluster.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/compute_cluster) | data source |
| [vsphere_datacenter.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/datacenter) | data source |
| [vsphere_datastore.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/datastore) | data source |
| [vsphere_network.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/network) | data source |
| [vsphere_resource_pool.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/resource_pool) | data source |
| [vsphere_virtual_machine.template](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/virtual_machine) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_datacenter"></a> [datacenter](#input\_datacenter) | Name of the vSphere datacenter the VM is created in | `string` | n/a | yes |
| <a name="input_datastore"></a> [datastore](#input\_datastore) | Name of the datastore backing the VM's disk | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Name of the port group / network the VM's NIC joins (DHCP is assumed) | `string` | n/a | yes |
| <a name="input_ssh_private_key"></a> [ssh\_private\_key](#input\_ssh\_private\_key) | PEM private key the kubeconfig fetch SSHes with. Its public half must be accepted by ssh\_user — bake it into the template or pass ssh\_public\_key. | `string` | n/a | yes |
| <a name="input_template"></a> [template](#input\_template) | Name of the VM template to clone. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (e.g. imported from ubuntu-24.04-server-cloudimg-amd64.ova) — a plain installer-built template ignores the guestinfo userdata and nothing boots k3s. | `string` | n/a | yes |
| <a name="input_cluster"></a> [cluster](#input\_cluster) | Name of the compute cluster to place the VM in (its root resource pool). Provide this OR resource\_pool. | `string` | `""` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Disk size in GB. Grown to at least the template's disk (vSphere can't shrink on clone). | `number` | `40` | no |
| <a name="input_folder"></a> [folder](#input\_folder) | VM folder to place the VM in. Empty = the datacenter root. | `string` | `""` | no |
| <a name="input_k3s_channel"></a> [k3s\_channel](#input\_k3s\_channel) | k3s release channel for the install script (stable, latest, or a minor like v1.31) | `string` | `"stable"` | no |
| <a name="input_k3s_extra_args"></a> [k3s\_extra\_args](#input\_k3s\_extra\_args) | Extra `k3s server` arguments appended to the install. The module always sets --disable traefik (the traefik/k8s module deploys Hub instead) and --write-kubeconfig-mode 644 (the SSH kubeconfig fetch reads it without sudo); servicelb stays enabled so LoadBalancer Services get the node IP. | `list(string)` | `[]` | no |
| <a name="input_kubeconfig_timeout"></a> [kubeconfig\_timeout](#input\_kubeconfig\_timeout) | Seconds the kubeconfig fetch waits for k3s to finish installing on first boot | `number` | `300` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB | `number` | `8192` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count. The default fits a demo hub (Traefik Hub + Keycloak + a Grafana stack). | `number` | `4` | no |
| <a name="input_resource_pool"></a> [resource\_pool](#input\_resource\_pool) | Name/path of the resource pool to place the VM in (e.g. "Cluster/Resources/demo"). Takes precedence over cluster. | `string` | `""` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key cloud-init authorizes for the template's default user at first boot. Empty = the template must already accept ssh\_private\_key. | `string` | `""` | no |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | SSH user the kubeconfig fetch logs in as (the Ubuntu cloud image default user is `ubuntu`) | `string` | `"ubuntu"` | no |
| <a name="input_static_gateway"></a> [static\_gateway](#input\_static\_gateway) | Default gateway for var.static\_ip. Ignored on DHCP. | `string` | `""` | no |
| <a name="input_static_ip"></a> [static\_ip](#input\_static\_ip) | Static address for the node, as CIDR (e.g. 10.10.10.10/24). Empty = DHCP. Needed where the network has no DHCP server, or where something downstream must know this node's address ahead of time — the demo's router publishes :80/:443 to it, so it cannot be a lease. | `string` | `""` | no |
| <a name="input_static_nameservers"></a> [static\_nameservers](#input\_static\_nameservers) | Resolvers for var.static\_ip. Ignored on DHCP. | `list(string)` | <pre>[<br/>  "8.8.8.8",<br/>  "1.1.1.1"<br/>]</pre> | no |
| <a name="input_tls_san"></a> [tls\_san](#input\_tls\_san) | Extra Subject Alternative Name for the k3s serving cert (--tls-san). The node's own IP is a SAN by default, so this is only needed to reach the API by another name (a DNS alias, a VIP). | `string` | `""` | no |
| <a name="input_update_kubeconfig"></a> [update\_kubeconfig](#input\_update\_kubeconfig) | Merge this cluster into the ambient kubeconfig (~/.kube/config, context k3s-<vm\_name>) after creation and switch the current context to it — the on-prem analogue of the cloud modules' `update_kubeconfig`. | `bool` | `true` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Name for the k3s VM (also its hostname) | `string` | `"k3s"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_client_certificate"></a> [client\_certificate](#output\_client\_certificate) | Admin client certificate (PEM) — k3s auth is cert-based, AKS/k3d-style |
| <a name="output_client_key"></a> [client\_key](#output\_client\_key) | Admin client key (PEM) |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Cluster CA certificate (PEM) |
| <a name="output_host"></a> [host](#output\_host) | Kubernetes API endpoint (https://<vm-ip>:6443) |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig (server rewritten from 127.0.0.1 to the VM IP) |
| <a name="output_node_ip"></a> [node\_ip](#output\_node\_ip) | The VM's guest IP — also where klipper (k3s servicelb) publishes LoadBalancer Services, so point demo DNS / /etc/hosts entries here |
| <a name="output_vm_id"></a> [vm\_id](#output\_vm\_id) | vSphere managed object ID of the k3s VM |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | Name of the k3s VM |
<!-- END_TF_DOCS -->