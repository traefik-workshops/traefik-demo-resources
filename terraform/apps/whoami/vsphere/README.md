# apps/whoami/vsphere

Provisions one or more Traefik `whoami` instances on vSphere VMs — the on-prem sibling of `apps/whoami/ec2` / `apps/whoami/azure-vm` / `apps/whoami/gce`, reusing the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `docker.io/zalbiraw/whoami`). Each replica is one small VM cloned from a user-provided **cloud-init-enabled Ubuntu cloud-image template**.

## The workload config is guestinfo JSON, not tags

vSphere tags and custom attributes must be **registered centrally** (in vCenter) before they can be attached to a VM — too heavy for free-form config. The Traefik Hub `vsphere` provider therefore reads **one extraConfig entry with key `guestinfo.traefik` whose value is a JSON object of Traefik labels** (the same JSON-blob story as GCE's `traefik` metadata item):

```json
{"traefik.enable": "true", "traefik.http.services.whoami.loadbalancer.server.port": "80"}
```

This module takes a `traefik_labels` map per app (dotted label → value) and `jsonencode()`s it into that entry. The provider's `constraints` expression matches **those same labels plus a synthesized `name` pseudo-label** (the VM name) — there is no separate label system. Note the provider does **no port discovery** (vSphere has no per-VM firewall primitive to read), so the `server.port` label is required.

## Example usage

```hcl
module "whoami_vsphere" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/apps/whoami/vsphere?ref=v4.3.0"

  datacenter = "dc-01"
  datastore  = "datastore-01"
  cluster    = "cluster-01"
  network    = "VM Network"
  template   = "ubuntu-24.04-cloudimg"

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-vsphere" # body shows `Name: whoami-vsphere`
      traefik_labels = {
        "traefik.enable"                                        = "true"
        "traefik.http.services.whoami.loadbalancer.server.port" = "80" # REQUIRED — no port discovery
      }
    }
  }
}
```

## Prerequisites

- vCenter credentials allowed to clone VMs; DHCP on the target network.
- A **cloud-init-enabled Ubuntu cloud-image template** (see `compute/vsphere/k3s`'s README for the import recipe). The cloud images ship `open-vm-tools`, which is what reports the guest IP — both this module's `instances` output and the vsphere provider's discovery depend on it.

## Notes

- The `instances` output exposes each VM's `private_ip` (its `default_ip_address`) — the Traefik child dials these in-network; the provider's `private` and `public` ipModes both resolve to this same primary guest address (no cloud public-IP concept).
- Per-VM ipMode override: the `traefik.vsphere.ipmode` label.
