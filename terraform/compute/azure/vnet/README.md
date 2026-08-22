# compute/azure/vnet

Demo VNet mirroring `compute/aws/vpc`: one VNet with a VM subnet, an ACI subnet (delegated to `Microsoft.ContainerInstance` — required for vnet-injected container groups), and an NSG opening the demo ports (80/443/8080/22 + `extra_ingress_ports`).

Exists because `compute/azure/aks` uses AKS-managed networking (the VNet lives in the `MC_*` node resource group), so there is no joinable VNet for the Azure VM / ACI spokes.

## Example usage

```hcl
module "vnet" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/azure/vnet?ref=v6.6.0"

  name                = "demo-vnet"
  resource_group_name = azurerm_resource_group.demo.name
  location            = "eastus"

  # Open the Hub multicluster uplink for VM/ACI spokes.
  extra_ingress_ports = [9443]
}
```

## Prerequisites

- An existing resource group; Azure credentials with Network permissions.

## Notes

- Only ACI container groups can live in the delegated `aci` subnet; VMs join the `vms` subnet.

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
| [azurerm_network_security_group.demo](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_rule.ingress](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_subnet.aci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.vms](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.aci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.vms](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_virtual_network.demo](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | VNet name. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the VNet (and NSG) are created in. | `string` | n/a | yes |
| <a name="input_aci_subnet_cidr"></a> [aci\_subnet\_cidr](#input\_aci\_subnet\_cidr) | CIDR block for the ACI subnet (delegated to Microsoft.ContainerInstance — only container groups can live here). Default carves a /24 out of the VNet CIDR. | `string` | `"10.0.2.0/24"` | no |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | VNet CIDR. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_extra_ingress_ports"></a> [extra\_ingress\_ports](#input\_extra\_ingress\_ports) | Additional TCP ports to open on the demo NSG (from any source), beyond the default 80/443/8080/22. Used for the Traefik Hub multicluster uplink entrypoint (:9443) on VM/ACI spokes the parent cluster dials. | `list(number)` | `[]` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure location. | `string` | `"eastus"` | no |
| <a name="input_vm_subnet_cidr"></a> [vm\_subnet\_cidr](#input\_vm\_subnet\_cidr) | CIDR block for the VM subnet. Default carves a /24 out of the VNet CIDR. | `string` | `"10.0.1.0/24"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_aci_subnet_id"></a> [aci\_subnet\_id](#output\_aci\_subnet\_id) | ID of the subnet delegated to Microsoft.ContainerInstance (for ACI container groups) |
| <a name="output_network_security_group_id"></a> [network\_security\_group\_id](#output\_network\_security\_group\_id) | Demo NSG ID |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Demo NSG ID as a one-element list (mirrors compute/aws/vpc) |
| <a name="output_vm_subnet_id"></a> [vm\_subnet\_id](#output\_vm\_subnet\_id) | ID of the subnet for VMs |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | VNet ID |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | VNet name |
<!-- END_TF_DOCS -->
