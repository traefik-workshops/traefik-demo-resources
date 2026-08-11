# compute/azure/aci

Shared `azurerm_container_group` fleet composed by both `traefik/aci` (the Hub multicluster child) and `apps/whoami/aci` (the whoami backend), the ACI analogue of `compute/aws/ec2`.

Owns ONLY the container group resource. Everything role-specific is rendered by the caller and passed in as opaque inputs: the container `commands` (the Traefik child inlines its `--hub.token`; whoami passes `/whoami --verbose`), the discovery `tags`, the container `environment_variables`, the file-provider secret `volumes`, and whether a system-assigned `identity` is attached. One container group is created per entry in `container_groups` — the traefik caller passes a single entry, whoami one per app replica.

## Example usage

```hcl
module "compute" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/azure/aci?ref=v6.1.4"

  resource_group_name = azurerm_resource_group.demo.name
  location            = "eastus"
  subnet_id           = module.vnet.aci_subnet_id # delegated to Microsoft.ContainerInstance

  container_name   = "whoami"
  image            = "ghcr.io/traefik-workshops/whoami:latest"
  container_cpu    = "0.5"
  container_memory = "1.0"
  commands         = ["/whoami", "--verbose"]

  container_groups = {
    "whoami-1" = {
      ports                 = [80]
      environment_variables = { WHOAMI_NAME = "whoami-1" }
      tags                  = { "traefik.enable" = "true" }
    }
  }
}
```

## Prerequisites

- An existing resource group and a subnet delegated to `Microsoft.ContainerInstance` for `Private` groups (see `compute/azure/vnet`).

## Notes

- ACI vnet-injected groups get a DHCP address from the delegated subnet; there is no static `private_ip` argument to pin (unlike the VM/EC2 siblings).
- `enable_system_identity` applies to every group in the call; when set, `instances[<key>].principal_id` exposes the identity for a downstream role assignment.
