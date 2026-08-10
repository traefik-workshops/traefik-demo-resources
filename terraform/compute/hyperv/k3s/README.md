# compute/hyperv/k3s

Single-node **k3s server on a Hyper-V VM** — the on-prem "managed k8s" stand-in, mirroring `compute/proxmox/k3s` / `compute/vsphere/k3s`. Composes the shared `compute/hyperv/vm` primitive (differencing VHDX + NoCloud seed ISO, built host-side over WinRM) and installs k3s at first boot with the bundled Traefik disabled (the `traefik/k8s` module deploys Hub instead); servicelb (klipper) stays on, so LoadBalancer Services get the node IP.

Two deliberate differences from the proxmox sibling:

- **Static addressing**: Hyper-V has no plan-readable guest-IP channel, so `ip_address` is an input delivered via the NoCloud network-config — `host`/`node_ip` are therefore **known at plan time**.
- **No qemu-guest-agent**: the golden parent bakes `linux-cloud-tools` (the Hyper-V KVP daemon) instead.

The admin kubeconfig is SSH-fetched (k3s mints client certs on the node; there is no API for them) and parsed into cert-based outputs; `update_kubeconfig` merges the cluster into `~/.kube/config` as context `k3s-<vm_name>`. On a NAT-internal lab subnet that SSH rides the operator's WireGuard tunnel — the tunnel must be up before the full apply (and before destroy, which refreshes the data source).

## Example usage

```hcl
module "k3s" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/hyperv/k3s?ref=v6.1.2"

  vm_name          = "hyperv-unified-ingress-k3s"
  host_winrm       = { host = "203.0.113.10", username = "Admin", password = var.host_admin_password }
  parent_vhdx_path = "C:\\traefik-lab\\golden\\noble-golden.vhdx"

  ip_address  = "10.99.0.10/24"
  gateway     = "10.99.0.1"
  dns_servers = ["10.99.0.2"] # the lab router's dnsmasq

  ssh_private_key = file("~/.ssh/id_ed25519")
  ssh_public_key  = trimspace(file("~/.ssh/id_ed25519.pub"))
}
```

## Prerequisites

- Everything `compute/hyperv/vm` needs (WinRM HTTPS on the host, the golden parent VHDX, the virtual switch).
- SSH reachability to the static node IP for the kubeconfig fetch (`ssh` + `jq` on the operator machine).
- `kubectl` on the operator machine when `update_kubeconfig = true`.
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_external"></a> [external](#provider\_external) | >= 2.0 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [null_resource.update_kubeconfig](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Default gateway for the node — the Hyper-V internal NAT switch's host-side address (e.g. 10.99.0.1). | `string` | n/a | yes |
| <a name="input_host_winrm"></a> [host\_winrm](#input\_host\_winrm) | WinRM HTTPS access to the Hyper-V HOST the VM is created on (see compute/hyperv/vm). | <pre>object({<br/>    host     = string<br/>    port     = optional(number, 5986)<br/>    username = string<br/>    password = string<br/>    https    = optional(bool, true)<br/>    insecure = optional(bool, true)<br/>    use_ntlm = optional(bool, true)<br/>    timeout  = optional(string, "10m")<br/>  })</pre> | n/a | yes |
| <a name="input_ip_address"></a> [ip\_address](#input\_ip\_address) | Static CIDR the node takes via the NoCloud network-config (e.g. 10.99.0.10/24). PLAN-KNOWN by design: it is also where klipper publishes LoadBalancer Services, so demo DNS wiring never waits on discovery. | `string` | n/a | yes |
| <a name="input_parent_vhdx_path"></a> [parent\_vhdx\_path](#input\_parent\_vhdx\_path) | Golden parent VHDX the differencing disk chains to — a generic Ubuntu CLOUD IMAGE (never the -azure.vhd) with linux-cloud-tools baked in (see compute/hyperv/vm). | `string` | n/a | yes |
| <a name="input_ssh_private_key"></a> [ssh\_private\_key](#input\_ssh\_private\_key) | PEM private key the kubeconfig fetch SSHes with. Its public half must be accepted by ssh\_user — pass ssh\_public\_key so cloud-init authorizes it at first boot. | `string` | n/a | yes |
| <a name="input_dns_servers"></a> [dns\_servers](#input\_dns\_servers) | DNS servers for the node. On the hyperv demo this is the lab router VM (dnsmasq: wildcard demo domain + public forwarding) — a static guest gets no DHCP, so forgetting this leaves the node unable to resolve anything. | `list(string)` | `[]` | no |
| <a name="input_k3s_channel"></a> [k3s\_channel](#input\_k3s\_channel) | k3s release channel for the install script (stable, latest, or a minor like v1.31) | `string` | `"stable"` | no |
| <a name="input_k3s_extra_args"></a> [k3s\_extra\_args](#input\_k3s\_extra\_args) | Extra `k3s server` arguments appended to the install. The module always sets --disable traefik (the traefik/k8s module deploys Hub instead) and --write-kubeconfig-mode 644 (the SSH kubeconfig fetch reads it without sudo); servicelb stays enabled so LoadBalancer Services get the node IP. | `list(string)` | `[]` | no |
| <a name="input_kubeconfig_timeout"></a> [kubeconfig\_timeout](#input\_kubeconfig\_timeout) | Seconds the kubeconfig fetch waits for k3s to finish installing on first boot | `number` | `300` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB (static — the module disables dynamic memory) | `number` | `8192` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count. The default fits a demo hub (Traefik Hub + Keycloak + a Grafana stack). | `number` | `4` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | Public key cloud-init authorizes for the image's default user at first boot. Empty = the golden image must already accept ssh\_private\_key. | `string` | `""` | no |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | SSH user the kubeconfig fetch logs in as (the Ubuntu cloud image default user is `ubuntu`) | `string` | `"ubuntu"` | no |
| <a name="input_switch_name"></a> [switch\_name](#input\_switch\_name) | Hyper-V virtual switch the VM's NIC joins. | `string` | `"traefik-lab"` | no |
| <a name="input_tls_san"></a> [tls\_san](#input\_tls\_san) | Extra Subject Alternative Name for the k3s serving cert (--tls-san). The node's own IP is a SAN by default, so this is only needed to reach the API by another name (a DNS alias, a VIP). | `string` | `""` | no |
| <a name="input_update_kubeconfig"></a> [update\_kubeconfig](#input\_update\_kubeconfig) | Merge this cluster into the ambient kubeconfig (~/.kube/config, context k3s-<vm\_name>) after creation and switch the current context to it — the on-prem analogue of the cloud modules' `update_kubeconfig`. | `bool` | `true` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Name for the k3s VM (also its hostname via the NoCloud meta-data, and the ambient kubeconfig context suffix k3s-<vm\_name>) | `string` | `"k3s"` | no |
| <a name="input_workdir"></a> [workdir](#input\_workdir) | Host directory the VM's seed + differencing disk live under. | `string` | `"C:\\traefik-lab"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_client_certificate"></a> [client\_certificate](#output\_client\_certificate) | Admin client certificate (PEM) — k3s auth is cert-based, AKS/k3d-style |
| <a name="output_client_key"></a> [client\_key](#output\_client\_key) | Admin client key (PEM) |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Cluster CA certificate (PEM) |
| <a name="output_host"></a> [host](#output\_host) | Kubernetes API endpoint (https://<static-node-ip>:6443) — known at PLAN time (static addressing) |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig (server rewritten from 127.0.0.1 to the VM IP) |
| <a name="output_node_ip"></a> [node\_ip](#output\_node\_ip) | The VM's static guest IP — also where klipper (k3s servicelb) publishes LoadBalancer Services, so point demo DNS / /etc/hosts entries here. An INPUT echoed back (Hyper-V has no plan-readable discovery), so it is plan-known. |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | Name of the k3s VM (no numeric VMID on Hyper-V — the name IS the identity) |
<!-- END_TF_DOCS -->
