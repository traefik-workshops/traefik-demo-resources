# apps/whoami/vsphere

Provisions one or more Traefik `whoami` instances on vSphere VMs — the on-prem sibling of `apps/whoami/ec2` / `apps/whoami/azure-vm` / `apps/whoami/gce`, reusing the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`). Each replica is one small VM cloned from a user-provided **cloud-init-enabled Ubuntu cloud-image template**.

## The workload config is LINE-format labels in the VM Notes

The Traefik Hub `vsphere` provider reads each VM's **Notes field (`config.annotation`) line by line** — one `traefik.key=value` per line, the same grammar the `proxmox` and `hyperv` siblings put in their guest descriptions. NOT JSON, not vCenter tags (a tag carries a name, not a map, and reading tags needs vCenter's vAPI), not custom attributes (registered centrally, and also vAPI). The Notes are free-form and hand-editable, so blank lines, `# comments` and free text around the block are tolerated; a `traefik.`-prefixed line without `=` is a typo and the provider skips the VM with a warning naming the line.

```
# managed by terraform
traefik.enable=true
traefik.http.services.whoami.loadbalancer.server.port=80
```

This module takes a `traefik_labels` map per app (dotted label → value) and renders it into that block. Two things follow from the provider's behaviour:

- **Same-named services across VMs MERGE** into one load balancer, so a fleet of N replicas carries one *identical* block and the gateway sees one N-server service. Per-service `loadbalancer.strategy` (leasttime/hrw) and `sticky.cookie` labels apply to the whole merged pool — which is how one fleet is published under several strategies. The block must be byte-identical per service across the fleet: differing settings for the same service name are a conflict and the service is dropped.
- There is **no port discovery** (vSphere has no per-VM firewall primitive to read), so the `server.port` label is required. The provider's `constraints` expression matches these same labels (`Label(\`traefik.tags\`, \`vm\`)` is the idiom to select one fleet among several on a shared vCenter), and `exposedByDefault` is false, so `traefik.enable=true` is mandatory.

## Example usage

```hcl
module "whoami_vsphere" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/vsphere?ref=v6.7.0"

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
      # One block for the whole fleet: both replicas merge into vmrr (wrr) and vmlt (leasttime).
      traefik_labels = {
        "traefik.enable"                                      = "true"
        "traefik.http.services.vmrr.loadbalancer.server.port" = "80" # REQUIRED — no port discovery
        "traefik.http.services.vmlt.loadbalancer.server.port" = "80"
        "traefik.http.services.vmlt.loadbalancer.strategy"    = "leasttime"
      }
    }
  }
}
```

## Prerequisites

- vCenter credentials allowed to clone VMs and set the VM Notes; DHCP on the target network (or `network_config` for static addresses).
- A **cloud-init-enabled Ubuntu cloud-image template** (see `compute/vsphere/k3s`'s README for the import recipe). The cloud images ship `open-vm-tools`, which is what reports the guest IP — both this module's `instances` output and the vsphere provider's discovery depend on it.

## Notes

- The `instances` output exposes each VM's `private_ip` (its `default_ip_address`) — the Traefik child dials these in-network; the provider's `private` and `public` ipModes both resolve to this same primary guest address (no cloud public-IP concept).
- Per-VM ipMode override: the `traefik.vsphere.ipmode` label.
- A label change is an in-place reconfigure of the VM's Notes (no replacement); the provider picks it up within its refresh interval.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |

## Providers

No providers.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_datacenter"></a> [datacenter](#input\_datacenter) | Name of the vSphere datacenter the VMs are created in | `string` | n/a | yes |
| <a name="input_datastore"></a> [datastore](#input\_datastore) | Name of the datastore backing the VMs' disks | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Name of the port group / network the VM NICs join. DHCP is assumed unless network\_config gives the instance a static address; either way the Traefik child dials each VM's guest IP. | `string` | n/a | yes |
| <a name="input_template"></a> [template](#input\_template) | Name of the VM template to clone. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (e.g. imported from ubuntu-24.04-server-cloudimg-amd64.ova) — a plain installer-built template ignores the guestinfo userdata and whoami never starts. | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to vSphere VMs. Each app can have multiple replicas. { name = { replicas, port, name, environment, traefik\_labels } } — `traefik_labels` (map of dotted Traefik labels, e.g. traefik.enable=true + traefik.http.services.<svc>.loadbalancer.server.port=80) is rendered line by line into each VM's Notes, which is where the Hub vsphere provider reads it; identical blocks on N replicas merge into one N-server service on the gateway. Optional `environment` (map) is merged over the module-level `environment` into the container. | `any` | `{}` | no |
| <a name="input_cluster"></a> [cluster](#input\_cluster) | Name of the compute cluster to place the VMs in (its root resource pool). Provide this OR resource\_pool. | `string` | `""` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Disk size in GB. Grown to at least the template's disk (vSphere can't shrink on clone). | `number` | `20` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_folder"></a> [folder](#input\_folder) | VM folder to place the VMs in. Empty = the datacenter root. | `string` | `""` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB per whoami VM | `number` | `1024` | no |
| <a name="input_network_config"></a> [network\_config](#input\_network\_config) | Per-instance cloud-init network-config v2, keyed by instance key (`<app>-<replica>`), passed straight through to compute/vsphere/vm and applied at BOOT. Use it on a network without DHCP, or when the VM's address must be a plan-time constant (a static server list, a scrape target). Empty = DHCP. | `any` | `{}` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count per whoami VM | `number` | `1` | no |
| <a name="input_resource_pool"></a> [resource\_pool](#input\_resource\_pool) | Name/path of the resource pool to place the VMs in. Takes precedence over cluster. | `string` | `""` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each VM. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server VMs with their details (private\_ip is the guest IP reported by open-vm-tools — vSphere VMs have one primary address, no cloud public-IP concept) |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Instance key -> guest IP, the shape the other whoami fleets expose (on vSphere the guest's one primary address). |
<!-- END_TF_DOCS -->