# compute/pnap/metal

On-demand phoenixNAP Bare Metal Cloud server (hourly pnap_server) — the native metal host for the private-cloud demos (Proxmox / ESXi / Ubuntu-Morpheus imaged per demo)

## Usage

```hcl
module "metal" {
  source = "git::https://github.com/<org>/traefik-demo.git//compute/pnap/metal?ref=vX.Y.Z"

  hostname = "pve-demo"
  type     = "d3.c2.medium"          # virtualization-worthy size; ESXi round wants >=128 GB RAM
  os       = "proxmox/proxmox9"      # or esxi/esxi80 (vSphere) / ubuntu/noble (Morpheus)
  ssh_keys = [file("~/.ssh/id_ed25519.pub")]
}
```

Billing is `HOURLY` by default — provision for a demo window, `terraform destroy` when done.
The pnap provider reads the operator credential from `~/.pnap/config.yaml` (client_id /
client_secret from the BMC portal), configured in the demo root — this module only
declares the requirement.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_pnap"></a> [pnap](#requirement\_pnap) | ~> 0.33 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_pnap"></a> [pnap](#provider\_pnap) | ~> 0.33 |

## Resources

| Name | Type |
| ---- | ---- |
| [pnap_server.metal](https://registry.terraform.io/providers/phoenixnap/pnap/latest/docs/resources/server) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | Server hostname (also the BMC display name). | `string` | n/a | yes |
| <a name="input_type"></a> [type](#input\_type) | BMC instance type (e.g. d3.c2.medium, s5.x6.c8.large — see phoenixnap.com/bare-metal-cloud/instances). Pick a virtualization-worthy size: the ESXi round wants >=128 GB RAM for VCSA + guests; the Proxmox/Morpheus rounds run comfortably on 64 GB. Cannot be changed after creation. | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | Free-text description shown in the BMC portal. | `string` | `"traefik-demo private-cloud host"` | no |
| <a name="input_install_default_ssh_keys"></a> [install\_default\_ssh\_keys](#input\_install\_default\_ssh\_keys) | Also install the account's default SSH keys. | `bool` | `true` | no |
| <a name="input_location"></a> [location](#input\_location) | BMC location ID (PHX, ASH, SGP, NLD, CHI, SEA, AUS). | `string` | `"PHX"` | no |
| <a name="input_management_access_allowed_ips"></a> [management\_access\_allowed\_ips](#input\_management\_access\_allowed\_ips) | IPs/CIDRs allowed to reach the server's management UI, scoped at the phoenixNAP network layer (single IP, CIDR, or range). For the proxmox/proxmox9 image this is the Proxmox web UI on :8006; the BMC portal calls it 'White Listed IPs'. Empty (default) means BMC ships the image locked down (Proxmox: :8006 firewalled to SSH-only) — set it to the operator's IP so the demo's terraform can reach the API. Applied at PROVISION time (no in-place update path in the provider): changing it re-images the server, so scope it up front. | `list(string)` | `[]` | no |
| <a name="input_network_type"></a> [network\_type](#input\_network\_type) | BMC network wiring. PUBLIC\_AND\_PRIVATE (default) gives the host a public IP for operator access plus the private backend network the demo guests NAT out of. | `string` | `"PUBLIC_AND_PRIVATE"` | no |
| <a name="input_os"></a> [os](#input\_os) | BMC OS image. The three the private-cloud demos use: proxmox/proxmox9 (Proxmox demo), esxi/esxi80 (vSphere demo — 60-day eval, deploy VCSA on top), ubuntu/noble (Morpheus demo — install the hpe-vm stack). Full list: the ServerCreate model in the BMC API docs. Changing it replaces the server. | `string` | `"proxmox/proxmox9"` | no |
| <a name="input_pricing_model"></a> [pricing\_model](#input\_pricing\_model) | Billing model. HOURLY is the point of this module — provision per demo, destroy after, pay for the window. Reservations only for a long-lived box. | `string` | `"HOURLY"` | no |
| <a name="input_ssh_keys"></a> [ssh\_keys](#input\_ssh\_keys) | SSH public keys installed on the server — the day-one access for the Linux images (proxmox/ubuntu). The ESXi image ignores these; use the generated root password output instead. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_id"></a> [id](#output\_id) | BMC server ID. |
| <a name="output_os"></a> [os](#output\_os) | The OS image the server was provisioned with. |
| <a name="output_password"></a> [password](#output\_password) | Generated root/admin password — the day-one access for the ESXi image (the Linux images use ssh\_keys instead). |
| <a name="output_private_ip_addresses"></a> [private\_ip\_addresses](#output\_private\_ip\_addresses) | Private (backend-network) IPs. |
| <a name="output_public_ip"></a> [public\_ip](#output\_public\_ip) | Primary public IP — where the operator (and the demo's terraform) reaches the hypervisor API (Proxmox :8006, ESXi/VCSA :443, Morpheus manager). |
| <a name="output_public_ip_addresses"></a> [public\_ip\_addresses](#output\_public\_ip\_addresses) | All public IPs assigned to the server. |
| <a name="output_status"></a> [status](#output\_status) | BMC provisioning status. |
<!-- END_TF_DOCS -->
