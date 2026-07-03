# traefik/vsphere-vm

Traefik Hub on a **vSphere VM** — the on-prem sibling of `traefik/ec2` / `traefik/azure-vm` / `traefik/oci-vm`. Clones a user-provided **cloud-init-enabled Ubuntu cloud-image template**, extracts its Traefik configuration from `traefik/shared` (via Helm template) and boots it with the shared `traefik/cloud-init` template — as a systemd binary, or as a docker container when `enable_preview_mode = true` (required while the `vsphere` provider isn't in a tagged Hub release).

## The vsphere provider

`var.vsphere_provider` renders `--hub.providers.vsphere.*` CLI flags. The gateway discovers workload VMs by their **`guestinfo.traefik` extraConfig entry** — a JSON object of dotted Traefik labels (see `apps/whoami/vsphere`); `constraints` match those labels plus a synthesized `name` pseudo-label. There is **no port discovery** (vSphere has no per-VM firewall primitive), so workloads must set the `server.port` label. `ipMode` `private` and `public` both resolve to a VM's primary guest IP (reported by open-vm-tools); `ipv6` picks the global IPv6 address.

**Credentials are explicit** — vSphere has no ambient identity (no instance profile / managed identity), so the provider takes `endpoint` + `username` (in the object) and `var.vsphere_password` (sensitive). Point them at a **read-only vCenter role**; the password lands in the VM's systemd unit / container args, which is demo-grade — don't reuse an admin credential.

Routerless discovery (`default_rule = "{{/*routerless*/}}"`) works exactly like the EC2/Azure/OCI siblings: VMs land as services only, and routers come from file-provider rules.

## Example usage

```hcl
module "traefik_vsphere" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/traefik/vsphere-vm?ref=v4.3.0"

  datacenter = "dc-01"
  datastore  = "datastore-01"
  cluster    = "cluster-01"
  network    = "VM Network"
  template   = "ubuntu-24.04-cloudimg"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  vsphere_provider = {
    endpoint   = "vcenter.lab.example.com"
    username   = "traefik-ro@vsphere.local"
    datacenter = "dc-01"
  }
  vsphere_password = var.vsphere_password

  # Join a Hub mesh: uplink entrypoint on :9443, parent dials this VM's guest IP.
  multicluster_provider = { enabled = true }
  custom_ports = {
    vmuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }
}
```

## Prerequisites

- vCenter credentials for terraform (clone rights) **plus** the read-only provider credential above — they can differ.
- A **cloud-init-enabled Ubuntu cloud-image template** (see `compute/vsphere/k3s`'s README); DHCP on the network; `helm` on the machine running terraform (config extraction via `helm template`).

## Notes

- `enable_dashboard_discovery` (default on) self-registers the VM's dashboard through its own `guestinfo.traefik` entry (`dashboard@vsphere`); disable it when a file-rule uplink advertises the dashboard instead.
- Outputs mirror the VM siblings (`instances` / `private_ips` / `public_ips`) so demo code reads identically — on vSphere both IP maps carry the same guest address.
