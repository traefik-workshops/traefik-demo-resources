# compute/azure/vm

Shared Azure Linux VM compute module. Provisions one `azurerm_linux_virtual_machine`
per replica from an `apps` map (keyed `<app>-<replica>`, mirroring
`compute/aws/ec2`), each with its own NIC, optional public IP, optional network
security group association, optional static private-IP pinning, opaque
pre-merged tags, and opaque cloud-init user data. Both `traefik/azure-vm` (the
multicluster gateway, `replicas = 1`) and `apps/whoami/azure-vm` (the echo
backends, `replicas = N`) compose it.

Role-specific concerns stay in the callers: cloud-init rendering, the Hub token,
discovery tags, dashboard self-registration, and NSG creation. The module
receives their results as opaque inputs, which is why the same module serves a
gateway and a workload without knowing which it is building.

`private_ips` is worth calling out. Pinning a VM's address is not cosmetic in
these demos: the hub dials each child gateway's uplink at a plan-known address,
so a pinned IP is what keeps `module.traefik` from having to depend on the child
being created first. The legs that pin (gcp, oci) are immune to an ordering
deadlock that the legs with computed addresses (aws ECS, azure ACI) had to
document their way around.

## Example usage

```hcl
module "vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/azure/vm?ref=v8.0.0"

  resource_group_name = azurerm_resource_group.demo.name
  location            = var.location
  subnet_id           = module.vnet.vm_subnet_id

  apps = {
    whoami = {
      replicas = 2
      tags     = local.discovery_tags
    }
  }

  admin_username = var.admin_username
  admin_password = var.admin_password
  user_data      = local.rendered_cloud_init
}
```

## Prerequisites

- A resource group and a subnet the NICs join.
- `admin_password` must satisfy Azure's complexity policy; the module does not
  generate one.
- `private_ips`, when set, must fall inside the subnet's range — Azure rejects a
  static allocation outside it at create time, not at plan time.

## Notes

- `identity_type` opts the VMs into a system-assigned managed identity;
  `principal_ids` then exposes it for a downstream role assignment (the pattern
  the ACI sibling uses to grant its child Reader on the resource group).
- `enable_network_security_group` and `network_security_group_id` are separate on
  purpose: a caller can build VMs into a subnet whose NSG it does not own.
- Unlike the ACI sibling, this module has no OTLP gate input. VM legs run
  `cloud-init-snippets/otlp-collector-gate.sh.tpl` from inside their rendered
  user data instead, so the wait lives in cloud-init rather than in an init
  container. The reason both exist is the same one recorded in
  `compute/azure/aci/README.md`: only the workload can tell a live collector from
  a DNS name still pointing at a destroyed load balancer.

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
| [azurerm_linux_virtual_machine.vm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_network_interface.vm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_network_interface_security_group_association.vm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_security_group_association) | resource |
| [azurerm_public_ip.vm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy as Azure Linux VMs, each with N replicas. Mirrors compute/aws/ec2's apps map (key -> { replicas, tags }). The instance key is "<app>-<replica>" — the VM, its NIC, and its optional public IP are all named off that key. | <pre>map(object({<br/>    replicas = optional(number, 1)<br/>    tags     = optional(map(string), {}) # Pre-merged, opaque discovery/role tags (dotted traefik.* keys, etc.)<br/>  }))</pre> | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the VMs (and their NICs/public IPs) are created in | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the existing subnet every VM NIC joins | `string` | n/a | yes |
| <a name="input_admin_password"></a> [admin\_password](#input\_admin\_password) | Admin password on the VMs. Default satisfies Azure's complexity rules; demo-grade only. | `string` | `"TopSecretPassword1!"` | no |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Admin username on the VMs (the cloud-init also creates the demo `traefiker` user) | `string` | `"azureuser"` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common tags applied to every VM (merged under each app's own tags, which win on collision) | `map(string)` | `{}` | no |
| <a name="input_enable_network_security_group"></a> [enable\_network\_security\_group](#input\_enable\_network\_security\_group) | Associate network\_security\_group\_id with the VM NICs. A separate config-known toggle because for\_each cannot depend on the id when it is created in the same run. | `bool` | `false` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Attach a Standard/Static public IP to each VM. | `bool` | `false` | no |
| <a name="input_identity_type"></a> [identity\_type](#input\_identity\_type) | Managed-identity type on the VMs (e.g. "SystemAssigned"). null = no identity block. The Traefik gateway passes "SystemAssigned" so DefaultAzureCredential inside the container resolves it via IMDS for the azureVM provider; the whoami backends leave it null. | `string` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure location | `string` | `"eastus"` | no |
| <a name="input_network_security_group_id"></a> [network\_security\_group\_id](#input\_network\_security\_group\_id) | NSG ID to associate with the VM NICs (used only when enable\_network\_security\_group = true; may be a same-run resource attribute). Subnet-level NSG rules still apply either way. | `string` | `""` | no |
| <a name="input_private_ips"></a> [private\_ips](#input\_private\_ips) | Fixed private IPs, one per instance index (instance idx N gets private\_ips[N]; extra instances fall back to Dynamic/DHCP). Each address must sit in subnet\_id's CIDR outside Azure's reserved first-4/last-1 hosts. Pinning makes the address plan-known AND stable across VM recreation — a hub dialing this child never goes stale. | `list(string)` | `[]` | no |
| <a name="input_replica_start_index"></a> [replica\_start\_index](#input\_replica\_start\_index) | Starting index for replica numbering (Default: 1) | `number` | `1` | no |
| <a name="input_user_data"></a> [user\_data](#input\_user\_data) | Map of instance key ("<app>-<replica>") -> already-rendered cloud-init/custom\_data. Opaque to this module: base64-encoded straight onto each VM's custom\_data. The caller owns all cloud-init rendering. | `map(string)` | `{}` | no |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | Azure VM size for every instance | `string` | `"Standard_B2s"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of instance key -> VM details (id, name, private\_ip, public\_ip) |
| <a name="output_principal_ids"></a> [principal\_ids](#output\_principal\_ids) | Map of instance key -> managed-identity principal id (null when identity\_type = null). The Traefik caller grants this principal Reader for the azureVM provider's discovery scope. |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance key -> private IP (pinned instances return their static address) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance key -> public IP (empty string when enable\_public\_ip = false) |
<!-- END_TF_DOCS -->
