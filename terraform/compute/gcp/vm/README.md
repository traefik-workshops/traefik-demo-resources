# compute/gcp/vm

The shared Google Compute Engine VM primitive. Owns the `google_compute_instance`
(one per `instances` map entry) and an optional `google_compute_firewall`, and
nothing role-specific: the caller renders its own cloud-init, assembles the GCE
`metadata` map (including the `user-data` item and the single dotted-label
`traefik` JSON workload item) and the dotless `labels`, then hands them in per
instance. Both `traefik/gce` (the multicluster gateway, one VM) and
`apps/whoami/gce` (the echo backends, N VMs) compose this module.

The `network_ip` static pin lives here (per instance) so a hub dialing a child's
private IP is plan-known and stable across VM recreation. An attached service
account (the `gce` provider's ADC identity) is passed via `service_account`;
leave it `null` for backends that need no identity.

## Example usage

```hcl
module "compute" {
  source = "../../compute/gcp/vm"

  instances = {
    "whoami-1" = {
      metadata = { user-data = module.cloud_init["whoami"].rendered }
      labels   = { app = "whoami" }
    }
  }

  machine_type     = "e2-micro"
  zone             = "us-central1-a"
  network          = "default"
  enable_public_ip = false

  enable_firewall        = true
  tags                   = ["whoami"]
  firewall_ports         = ["80"]
  firewall_source_ranges = ["10.0.0.0/8"]
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [google_compute_firewall.vm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_instance.vm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_instances"></a> [instances](#input\_instances) | Map of VM key -> per-instance config. The key becomes the VM `name`<br/>(callers use the "<app>-<replica>" scheme, e.g. "traefik-1", "whoami-1").<br/>- metadata:   the full GCE metadata map, already assembled by the caller<br/>              (includes the `user-data` cloud-init item and, on GCE, the<br/>              single `traefik` JSON workload item — metadata keys can't<br/>              contain dots, so provider labels ride inside that item).<br/>- labels:     dotless GCE labels (provider constraints only).<br/>- network\_ip: fixed internal IP for the primary NIC (network\_interface<br/>              .network\_ip). Must sit in the instance's subnetwork range.<br/>              Empty = ephemeral/DHCP. Pinning makes a hub's uplink dial<br/>              address plan-known and stable across VM recreation. | <pre>map(object({<br/>    metadata   = map(string)<br/>    labels     = optional(map(string), {})<br/>    network_ip = optional(string, "")<br/>  }))</pre> | n/a | yes |
| <a name="input_boot_disk_type"></a> [boot\_disk\_type](#input\_boot\_disk\_type) | Boot disk type | `string` | `"pd-standard"` | no |
| <a name="input_enable_firewall"></a> [enable\_firewall](#input\_enable\_firewall) | Create a firewall rule opening firewall\_ports to the VMs from firewall\_source\_ranges (mirrors compute/azure/vnet's NSG idea — GCP firewalls are VPC-scoped, so the rule lives with the VMs it targets). Disable when the network already allows it (e.g. default network's default-allow-internal). | `bool` | `false` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Attach an ephemeral public IP to each VM (adds an empty access\_config block). Off by default — callers dial the private IP in-network. | `bool` | `false` | no |
| <a name="input_firewall_ports"></a> [firewall\_ports](#input\_firewall\_ports) | TCP ports (as strings) the firewall rule opens on the VMs. | `list(string)` | `[]` | no |
| <a name="input_firewall_source_ranges"></a> [firewall\_source\_ranges](#input\_firewall\_source\_ranges) | Source CIDR ranges allowed by the firewall rule. | `list(string)` | <pre>[<br/>  "10.0.0.0/8"<br/>]</pre> | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | GCE machine type applied to every instance | `string` | `"e2-medium"` | no |
| <a name="input_network"></a> [network](#input\_network) | VPC network the VMs join | `string` | `"default"` | no |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Optional attached service account (ADC identity). null = no service\_account block on the VMs. | <pre>object({<br/>    email  = string<br/>    scopes = list(string)<br/>  })</pre> | `null` | no |
| <a name="input_subnetwork"></a> [subnetwork](#input\_subnetwork) | Subnetwork the VMs join. Empty = let GCP pick the network's subnet in the zone's region (works on auto-mode networks like `default`). | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Network tags applied to every VM (firewall targeting, dotless). The firewall rule name is derived from the first tag. | `list(string)` | `[]` | no |
| <a name="input_vm_image"></a> [vm\_image](#input\_vm\_image) | Boot disk image (family or self link) | `string` | `"ubuntu-os-cloud/ubuntu-2404-lts-amd64"` | no |
| <a name="input_zone"></a> [zone](#input\_zone) | GCE zone the VMs are created in | `string` | `"us-central1-a"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of VM key -> details (keyed like the input: <app>-<replica>). |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of VM key -> private IP address. |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of VM key -> public IP address (empty string when enable\_public\_ip = false). |
<!-- END_TF_DOCS -->
