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
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/compute/morpheus/k3s?ref=v4.3.0"

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
