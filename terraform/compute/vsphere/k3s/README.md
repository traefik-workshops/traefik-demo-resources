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
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/compute/vsphere/k3s?ref=v4.3.0"

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
