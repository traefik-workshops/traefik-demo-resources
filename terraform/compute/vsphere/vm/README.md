# compute/vsphere/vm

Shared **vSphere VM fleet** — the single infra module behind both `traefik/vsphere-vm` (one gateway VM) and `apps/whoami/vsphere` (N workload VMs). Clones a cloud-init-enabled Ubuntu cloud-image template into one `vsphere_virtual_machine` per instance key (`<app>-<replica>`), and owns the datacenter/datastore/cluster/resource_pool/network/template data lookups.

Role-agnostic by design: cloud-init is rendered by the caller and passed in as opaque `user_data`; the vsphere provider's workload config (the `guestinfo.traefik` entry) is built by the caller and passed in as opaque `extra_config` guestinfo entries. Outputs mirror the other `compute/*` modules (`instances` / `private_ips` / `public_ips`) — on vSphere both IP maps carry the same primary guest address.

## Example usage

```hcl
module "vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/vsphere/vm?ref=v5.3.0"

  datacenter = "dc-01"
  datastore  = "datastore-01"
  cluster    = "cluster-01"
  network    = "VM Network"
  template   = "ubuntu-24.04-cloudimg"

  apps = {
    whoami = { replicas = 2 }
  }

  user_data = {
    "whoami-1" = local.rendered_cloud_init
    "whoami-2" = local.rendered_cloud_init
  }

  extra_config = {
    "whoami-1" = { "guestinfo.traefik" = jsonencode(local.traefik_labels) }
    "whoami-2" = { "guestinfo.traefik" = jsonencode(local.traefik_labels) }
  }
}
```

## Prerequisites

- vCenter credentials allowed to clone VMs; DHCP on the target network.
- A **cloud-init-enabled Ubuntu cloud-image template** (see `compute/vsphere/k3s`'s README for the import recipe). The cloud images ship `open-vm-tools`, which reports the guest IP the `instances` output and the vsphere provider's discovery both depend on.
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
