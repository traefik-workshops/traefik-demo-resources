# apps/whoami/azure-vm

Provisions one or more Traefik `whoami` instances on Azure Linux VMs — the Azure sibling of `apps/whoami/ec2`, reusing the `whoami/cloud-init` template (systemd unit + binary extraction). The `apps` map reads identically to the EC2 module.

Each VM's Azure tags (dotted `traefik.*` keys, exactly like EC2 instance tags) are the workload config a Traefik Hub `azureVM` provider (`traefik/azure-vm`) discovers.

## Example usage

```hcl
module "whoami_azure_vm" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/apps/whoami/azure-vm?ref=v4.3.0"

  resource_group_name = azurerm_resource_group.demo.name
  subnet_id           = module.vnet.vm_subnet_id

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-azure-vm" # body shows `Name: whoami-azure-vm`
      tags = {
        "traefik.enable"                                          = "true"
        "traefik.http.services.whoami.loadbalancer.server.port" = "80"
      }
    }
  }
}
```

## Prerequisites

- Azure credentials with Compute/Network permissions and an existing resource group.
- An existing subnet to join (e.g. `compute/azure/vnet`'s `vm_subnet_id`) — or set `create_vnet = true`.

## Notes

- VMs get private IPs by default (`enable_public_ip = false`) — the Traefik child dials them in-vnet (`ipMode=private`).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.0 |

## Resources

| Name | Type |
|------|------|
| [azurerm_linux_virtual_machine.whoami](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_network_interface.whoami](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_network_interface_security_group_association.whoami](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_security_group_association) | resource |
| [azurerm_public_ip.whoami](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the VMs are created in | `string` | n/a | yes |
| <a name="input_admin_password"></a> [admin\_password](#input\_admin\_password) | Admin password on the VMs. Default satisfies Azure's complexity rules; demo-grade only. | `string` | `"TopSecretPassword1!"` | no |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Admin username on the VMs (the cloud-init also creates the demo `traefiker` user) | `string` | `"azureuser"` | no |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to Azure VMs. Each app can have multiple replicas. Same shape as apps/whoami/ec2: { name = { replicas, port, name, tags } }. | `any` | `{}` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common tags to apply to all VMs | `map(string)` | `{}` | no |
| <a name="input_create_vnet"></a> [create\_vnet](#input\_create\_vnet) | Create a demo VNet (compute/azure/vnet) if subnet\_id is not provided. Off by default — these VMs normally join an existing VNet. | `bool` | `false` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Attach a public IP to each VM. Off by default — the Traefik child dials private IPs (ipMode=private). | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure location | `string` | `"eastus"` | no |
| <a name="input_network_security_group_id"></a> [network\_security\_group\_id](#input\_network\_security\_group\_id) | NSG ID to associate with the VM NICs. Empty = no NIC-level NSG (subnet-level NSG rules still apply). | `string` | `""` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the existing subnet the VM NICs join | `string` | `""` | no |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | Azure VM size for all echo servers | `string` | `"Standard_B1s"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | The Whoami version to install. Must be a real traefik/whoami image tag — they carry a `v` prefix (e.g. v1.11.0); a bare `1.11.0` is `manifest unknown` and the binary extraction silently fails. | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server VMs with their details |
<!-- END_TF_DOCS -->
