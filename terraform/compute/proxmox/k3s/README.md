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
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/compute/proxmox/k3s?ref=v4.3.0"

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
