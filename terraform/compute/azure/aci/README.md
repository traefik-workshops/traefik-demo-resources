# compute/azure/aci

Shared `azurerm_container_group` fleet composed by both `traefik/aci` (the Hub multicluster child) and `apps/whoami/aci` (the whoami backend), the ACI analogue of `compute/aws/ec2`.

Owns ONLY the container group resource. Everything role-specific is rendered by the caller and passed in as opaque inputs: the container `commands` (the Traefik child inlines its `--hub.token`; whoami passes `/whoami --verbose`), the discovery `tags`, the container `environment_variables`, the file-provider secret `volumes`, and whether a system-assigned `identity` is attached. One container group is created per entry in `container_groups` — the traefik caller passes a single entry, whoami one per app replica.

## Example usage

```hcl
module "compute" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/azure/aci?ref=v6.7.0"

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

## The OTLP collector gate

Set `otlp_gate_address` whenever the workload exports telemetry:

```hcl
otlp_gate_address = "https://collector.example.com"
```

It adds an init container that blocks the workload from starting until that endpoint
**accepts an OTLP write** — bounded at 30 minutes, then starts anyway. It is the container-native counterpart of the
`cloud-init-snippets/otlp-collector-gate.sh.tpl` every VM leg runs on first boot — same
intent, same 30-minute bound, but it verifies TLS (see the notes below) and is delivered as
an init container, because the workload images here are scratch with no cloud-init to hook.

Why it is not optional in practice: an exporter that makes its first export against an
endpoint that is not up yet goes dark for **30–45 minutes** before it recovers on its own.
Measured on azure-unified-ingress (2026-08-11): the ACI whoami booted at 13:13:40, failed
every export through at least 13:34:25, and had healed by roughly 14:00.

That is worse than a clean failure. The demo serves every request perfectly and reports
nothing for the first half hour somebody might be presenting it, and the service-map
assertion then passes or fails on how long the harness happened to take to reach it — the
run before that one, sampling ~35 minutes after the same boot, came back missing
`whoami-container` and failed. The gate replaces that coin flip with telemetry from the
first request.

**Do not gate a container the collector's own existence depends on.** In the unified-ingress
demos the hub consumes the ACI *gateway's* private IP as its uplink address, and the hub is
what brings the collector up — so gating that container makes it wait for an endpoint that
cannot exist until it starts. Bounded at 30 minutes instead of fatal, which reads as a slow
demo rather than a broken one and is harder to find. `traefik/aci` therefore leaves the gate
off and says so; `apps/whoami/aci` turns it on, because nothing is built on top of a backend.
Trace what consumes a container's outputs before gating it.

**Terraform-side ordering does not substitute for this.** `observability/dns-gate` waits for
the collector's DNS name to resolve, and a name resolves perfectly well while it still points
at the *previous* run's load balancer: on azure-unified-ingress (2026-08-11) that gate
returned `resolves -- spokes may boot` in one second, against an IP whose resource group had
already been destroyed. In these demos it is also upstream of the hub that publishes the
record, so on a genuinely cold domain it waits for something its own dependents must be
created before anything can publish. Only the workload can ask the question that settles it,
and only from inside its own network.

## Notes

- ACI vnet-injected groups get a DHCP address from the delegated subnet; there is no static `private_ip` argument to pin (unlike the VM/EC2 siblings).
- `enable_system_identity` applies to every group in the call; when set, `instances[<key>].principal_id` exposes the identity for a downstream role assignment.
- `otlp_gate_image` only needs a shell and curl. It defaults to an **MCR** image, not Docker Hub: ACI's anonymous Docker Hub pulls are rate-limited, and creating a group from `curlimages/curl` returned `RegistryErrorResponse ... index.docker.io` on the very first try (azure-unified-ingress, 2026-08-11). A gate that cannot pull is a group that never starts, which is a far worse failure than the one it prevents.
- Init containers run to completion in order before the main container, and the gate always exits 0 — a non-zero exit would leave the group restarting instead of degrading to "runs, reports late".
- The probe **verifies the certificate**, and deliberately does not reuse the shared cloud-init snippet, which probes with `curl -skf`. That `-k` opens the gate while Traefik is still serving its own default self-signed cert, before Let's Encrypt has issued — and the workload's SDK verifies, so it fails anyway. Measured on azure-unified-ingress (2026-08-11): the gate printed `OTLP collector ready.` on its first attempt and the whoami it released then logged 62 consecutive `x509: certificate is valid for ...traefik.default`. The gate installs `ca-certificates` first (the base image ships none: curl exits 60, `ssl_verify_result=20`) and degrades loudly to insecure if that install fails.

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
| [azurerm_container_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_container_groups"></a> [container\_groups](#input\_container\_groups) | Map of container groups to create, keyed by the group name (the map key IS azurerm\_container\_group.name — the traefik caller passes a single entry keyed by its group name, the whoami caller passes one entry per app replica: `<app>-<replica>`). Each entry carries only the per-group config that varies between groups; everything shared (image, cpu, memory, commands, ...) is a module-level input. | <pre>map(object({<br/>    ports                 = optional(list(number), []) # container-level exposed ports (one `ports {}` block each)<br/>    environment_variables = optional(map(string), {})  # container env vars (already merged by the caller)<br/>    tags                  = optional(map(string), {})  # per-group tags, merged over common_tags<br/>  }))</pre> | n/a | yes |
| <a name="input_container_name"></a> [container\_name](#input\_container\_name) | Name of the single container inside each group (e.g. "traefik" or "whoami") | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | Fully-qualified container image every group runs (already resolved by the caller — this module does no tag inference) | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the container groups are created in | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the existing subnet every container group joins. For a Private ip\_address\_type it MUST be delegated to Microsoft.ContainerInstance (compute/azure/vnet's aci\_subnet\_id already is). | `string` | n/a | yes |
| <a name="input_commands"></a> [commands](#input\_commands) | Container `commands` (REPLACES the image entrypoint). Rendered by the caller — the Traefik child inlines its --hub.token here, whoami passes ["/whoami", "--verbose"]. | `list(string)` | `[]` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Tags applied to every container group, merged UNDER each group's per-group tags (per-group wins on collision) | `map(string)` | `{}` | no |
| <a name="input_container_cpu"></a> [container\_cpu](#input\_container\_cpu) | vCPU allocation for the container | `string` | `"1.0"` | no |
| <a name="input_container_memory"></a> [container\_memory](#input\_container\_memory) | Memory allocation (GB) for the container | `string` | `"2.0"` | no |
| <a name="input_enable_system_identity"></a> [enable\_system\_identity](#input\_enable\_system\_identity) | Attach a system-assigned managed identity to every container group (the Traefik child needs one for the aci provider's DefaultAzureCredential; whoami does not). | `bool` | `false` | no |
| <a name="input_exposed_ports"></a> [exposed\_ports](#input\_exposed\_ports) | Group-level `exposed_port` blocks (all TCP). A private container group must declare every port it serves. Empty means no group-level exposed\_port blocks (whoami relies on container `ports` only). | `list(number)` | `[]` | no |
| <a name="input_ip_address_type"></a> [ip\_address\_type](#input\_ip\_address\_type) | Container group IP address type. `Private` gives a vnet-injected IP (the default for these demo spokes); `Public` gives a public IP + FQDN. | `string` | `"Private"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure location | `string` | `"eastus"` | no |
| <a name="input_os_type"></a> [os\_type](#input\_os\_type) | Container group OS type | `string` | `"Linux"` | no |
| <a name="input_otlp_gate_address"></a> [otlp\_gate\_address](#input\_otlp\_gate\_address) | OTLP collector base URL (e.g. https://collector.example.com). When set, an init container blocks the workload from starting until that endpoint ACCEPTS an OTLP write — the container-native form of cloud-init-snippets/otlp-collector-gate.sh.tpl, which every VM leg already runs. Empty disables the gate. Set it whenever the workload exports telemetry: a container that starts against a collector that is not up yet, or against a stale DNS record still pointing at a destroyed load balancer, goes dark for 30-45 minutes before it recovers on its own — long enough to make the service map a coin flip, and terraform-side ordering cannot fix it. | `string` | `""` | no |
| <a name="input_otlp_gate_image"></a> [otlp\_gate\_image](#input\_otlp\_gate\_image) | Image the OTLP gate init container runs. Needs only a shell and curl — the workload images (Hub, whoami) are scratch, which is why the probe cannot live inside them. Defaults to an MCR image ON PURPOSE: ACI's anonymous pulls from Docker Hub are rate-limited, and a gate that cannot pull is a group that never starts. Measured 2026-08-11 on azure-unified-ingress, creating a group from curlimages/curl: 'RegistryErrorResponse: An error response is received from the docker registry index.docker.io'. MCR is Azure-native and imposes no such limit. | `string` | `"mcr.microsoft.com/azurelinux/base/core:3.0"` | no |
| <a name="input_restart_policy"></a> [restart\_policy](#input\_restart\_policy) | Container group restart policy | `string` | `"Always"` | no |
| <a name="input_volumes"></a> [volumes](#input\_volumes) | Secret volumes mounted into the container. Rendered by the caller (the Traefik child mounts its file-provider config as a secret volume; whoami mounts none). `secret` maps a file name to its base64-encoded content. | <pre>list(object({<br/>    name       = string<br/>    mount_path = string<br/>    secret     = map(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all container groups with their details, keyed by group name |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of group name to private (vnet-injected) IP address |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of group name to public IP address (null for Private ip\_address\_type) |
<!-- END_TF_DOCS -->
