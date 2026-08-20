# apps/whoami/azure-vm

Provisions one or more Traefik `whoami` instances on Azure Linux VMs — the Azure sibling of `apps/whoami/ec2`, reusing the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`). The `apps` map reads identically to the EC2 module.

Each VM's Azure tags (dotted `traefik.*` keys, exactly like EC2 instance tags) are the workload config a Traefik Hub `azureVM` provider (`traefik/azure-vm`) discovers.

## Example usage

```hcl
module "whoami_azure_vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/azure-vm?ref=v6.3.1"

  resource_group_name = azurerm_resource_group.demo.name
  subnet_id           = module.vnet.vm_subnet_id

  # OTel config for the instrumented fork — passed to every container via docker -e
  # (per-app `environment` entries win on collision).
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_SERVICE_NAME           = "whoami-azure-vm"
  }

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
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cloud_init"></a> [cloud\_init](#module\_cloud\_init) | ../cloud-init | n/a |
| <a name="module_vm"></a> [vm](#module\_vm) | ../../../compute/azure/vm | n/a |
| <a name="module_vnet"></a> [vnet](#module\_vnet) | ../../../compute/azure/vnet | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the VMs are created in | `string` | n/a | yes |
| <a name="input_admin_password"></a> [admin\_password](#input\_admin\_password) | Admin password on the VMs. Default satisfies Azure's complexity rules; demo-grade only. | `string` | `"TopSecretPassword1!"` | no |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Admin username on the VMs (the cloud-init also creates the demo `traefiker` user) | `string` | `"azureuser"` | no |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to Azure VMs. Each app can have multiple replicas. Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container. | `any` | `{}` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common tags to apply to all VMs | `map(string)` | `{}` | no |
| <a name="input_create_vnet"></a> [create\_vnet](#input\_create\_vnet) | Create a demo VNet (compute/azure/vnet) if subnet\_id is not provided. Off by default — these VMs normally join an existing VNet. | `bool` | `false` | no |
| <a name="input_enable_network_security_group"></a> [enable\_network\_security\_group](#input\_enable\_network\_security\_group) | Associate network\_security\_group\_id with the VM NICs. A separate config-known toggle because for\_each cannot depend on the id when it is created in the same run. | `bool` | `false` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Attach a public IP to each VM. Off by default — the Traefik child dials private IPs (ipMode=private). | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure location | `string` | `"eastus"` | no |
| <a name="input_network_security_group_id"></a> [network\_security\_group\_id](#input\_network\_security\_group\_id) | NSG ID to associate with the VM NICs (used only when enable\_network\_security\_group = true or create\_vnet = true; may be a same-run resource attribute). Subnet-level NSG rules still apply either way. | `string` | `""` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the existing subnet the VM NICs join | `string` | `""` | no |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | Azure VM size for all echo servers | `string` | `"Standard_B1s"` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each VM. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server VMs with their details |
<!-- END_TF_DOCS -->
