# compute/azure/desktop

A generic **Demo Studio recording workstation** on Azure: Ubuntu 24.04 + GNOME + xrdp on a dummy
Xorg pinned to 1920×1080, the full dev toolchain, and the recording stack (ffmpeg, wmctrl, xdotool).
One VM serves any demo's `record-section` — it runs no gateway.

Forked from [`terraform/traefik/azure-vm`](../../../traefik/azure-vm) (VM/NIC/pip/identity/role
skeleton) with the entire Traefik-Hub surface dropped. Provisioned by [`cloud-init/desktop.tpl`](./cloud-init/desktop.tpl).

- **Capture on the VM** (ffmpeg x11grab against the pinned `:10` display); **RDP is watch-only**.
- **Phase A** (default): vanilla Ubuntu + cloud-init (~15 min first boot). **Phase B**: set
  `source_image_id` to a Shared Image Gallery golden image for ~2-min boots + frozen tool versions.
- Lock `source_address_prefix` to your operator IP — the NSG opens SSH (22) + RDP (3389).
- Secrets: prefer the managed identity for Azure; inject the git deploy key / API keys via
  `extra_files` (0600). ElevenLabs runs off the VM — its key never lands here.

Driven by the `vm-standup` / `vm-teardown` skills; consumed via `recording-target.yaml`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_linux_virtual_machine.desktop](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_network_interface.desktop](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_network_interface_security_group_association.desktop](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_security_group_association) | resource |
| [azurerm_network_security_group.desktop](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_public_ip.desktop](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_role_assignment.identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_password"></a> [admin\_password](#input\_admin\_password) | Admin password (demo-grade; used for SSH + RDP + sudo). Set to a strong value. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group to create the recording workstation in. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Subnet to attach the NIC to (e.g. compute/azure/vnet vm\_subnet\_id). | `string` | n/a | yes |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Admin/login user (matches the hand-built workstation). | `string` | `"traefik"` | no |
| <a name="input_dev_toolchain"></a> [dev\_toolchain](#input\_dev\_toolchain) | Per-tool install toggles. Default installs the full workstation toolchain. | <pre>object({<br/>    chrome         = optional(bool, true)<br/>    vscode         = optional(bool, true)<br/>    postman        = optional(bool, true)<br/>    bruno          = optional(bool, true)<br/>    claude_desktop = optional(bool, true)<br/>    claude_code    = optional(bool, true)<br/>    gh             = optional(bool, true)<br/>    terraform      = optional(bool, true)<br/>    az_cli         = optional(bool, true)<br/>    gcloud         = optional(bool, true)<br/>    aws_cli        = optional(bool, true)<br/>    eksctl         = optional(bool, true)<br/>    docker         = optional(bool, true)<br/>    k3d            = optional(bool, true)<br/>    helm           = optional(bool, true)<br/>    kubectl        = optional(bool, true)<br/>    kubectx        = optional(bool, true)<br/>    krew           = optional(bool, true)<br/>    k9s            = optional(bool, true)<br/>  })</pre> | `{}` | no |
| <a name="input_enable_contributor_role"></a> [enable\_contributor\_role](#input\_enable\_contributor\_role) | Grant Contributor instead of Reader (only if the desktop itself runs `make up` / provisions cloud infra). | `bool` | `false` | no |
| <a name="input_enable_nsg"></a> [enable\_nsg](#input\_enable\_nsg) | Create a dedicated NSG allowing SSH + RDP from source\_address\_prefix and associate it to the NIC. | `bool` | `true` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Allocate a public IP so the operator can RDP/SSH in. Lock it down with source\_address\_prefix. | `bool` | `true` | no |
| <a name="input_enable_reader_role"></a> [enable\_reader\_role](#input\_enable\_reader\_role) | Grant the VM identity Reader on the resource group (so `az login --identity` works read-only on the VM). | `bool` | `true` | no |
| <a name="input_enable_recording_toolchain"></a> [enable\_recording\_toolchain](#input\_enable\_recording\_toolchain) | Install the recording stack (ffmpeg, wmctrl, xdotool, cursor-highlight) + the claude-in-chrome extension bootstrap. | `bool` | `true` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Extra files written by cloud-init (secrets, config) — { path, content, permissions }. | <pre>list(object({<br/>    path        = string<br/>    content     = string<br/>    permissions = optional(string, "0644")<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Extra tags to apply to the VM. | `map(string)` | `{}` | no |
| <a name="input_git_deploy_key"></a> [git\_deploy\_key](#input\_git\_deploy\_key) | Private SSH deploy key (RW) for the demo repo, written to ~/.ssh so git pull/push works headlessly. Empty = skip. | `string` | `""` | no |
| <a name="input_git_repo_url"></a> [git\_repo\_url](#input\_git\_repo\_url) | SSH URL of the demo repo to clone to ~/traefik-demo (used only when git\_deploy\_key is set). | `string` | `"git@github.com:traefik-workshops/traefik-demo.git"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | `"eastus"` | no |
| <a name="input_os_disk_size_gb"></a> [os\_disk\_size\_gb](#input\_os\_disk\_size\_gb) | OS disk size in GB. | `number` | `100` | no |
| <a name="input_os_disk_type"></a> [os\_disk\_type](#input\_os\_disk\_type) | OS disk storage account type. Premium for smooth capture I/O. | `string` | `"Premium_LRS"` | no |
| <a name="input_rdp_color_depth"></a> [rdp\_color\_depth](#input\_rdp\_color\_depth) | Color depth for xrdp/Xorg (24 for clean capture). | `number` | `24` | no |
| <a name="input_rdp_resolution"></a> [rdp\_resolution](#input\_rdp\_resolution) | Pinned desktop resolution for the dummy Xorg display ffmpeg captures. | `string` | `"1920x1080"` | no |
| <a name="input_source_address_prefix"></a> [source\_address\_prefix](#input\_source\_address\_prefix) | CIDR/IP allowed to reach SSH (22) + RDP (3389). STRONGLY recommend your operator IP, not '*'. | `string` | `"*"` | no |
| <a name="input_source_image_id"></a> [source\_image\_id](#input\_source\_image\_id) | Optional Shared Image Gallery image id (Phase B golden image). Empty = vanilla Ubuntu 24.04 + cloud-init (Phase A). | `string` | `""` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Base name for the VM, NIC, public IP, and NSG. | `string` | `"demo-desktop"` | no |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | VM size. Default is 4 vCPU / 16 GB (D-series, not burstable B — B stutters on screen capture). | `string` | `"Standard_D4s_v5"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | Principal ID of the VM's system-assigned managed identity. |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | Private IP on the subnet. |
| <a name="output_public_ip"></a> [public\_ip](#output\_public\_ip) | Public IP (empty when enable\_public\_ip = false). |
| <a name="output_rdp_endpoint"></a> [rdp\_endpoint](#output\_rdp\_endpoint) | host:3389 for xfreerdp/RDP (watch-only; capture happens on the VM). |
| <a name="output_ssh_endpoint"></a> [ssh\_endpoint](#output\_ssh\_endpoint) | user@host:22 for SSH (the primary agent driver). |
| <a name="output_vm_id"></a> [vm\_id](#output\_vm\_id) | The recording VM's resource id. |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | The recording VM's name. |
<!-- END_TF_DOCS -->
