# apps/whoami/oci-vm

Provisions one or more Traefik `whoami` instances on OCI Compute VMs — the OCI sibling of `apps/whoami/ec2` and `apps/whoami/azure-vm`, reusing the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`). The `apps` map reads identically to the EC2 module.

Each VM's freeform tags (dotted `traefik.*` keys, exactly like EC2 instance tags) are the workload config a Traefik Hub `oci` provider (`traefik/oci-vm`) discovers.

## Example usage

```hcl
module "whoami_oci_vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/oci-vm?ref=v8.1.0"

  compartment_id = var.compartment_id
  subnet_id      = module.oke.nodes_subnet_id

  # OTel config for the instrumented fork — passed to every container via docker -e
  # (per-app `environment` entries win on collision).
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_SERVICE_NAME           = "whoami-oci-vm"
  }

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-oci-vm" # body shows `Name: whoami-oci-vm`
      tags = {
        "traefik.enable"                                         = "true"
        "traefik.http.services.whoami.loadbalancer.server.port" = "80"
      }
    }
  }
}
```

## Prerequisites

- OCI credentials with Compute/Network permissions and an existing compartment.
- An existing subnet to join (e.g. `compute/oracle/oke`'s `nodes_subnet_id` — its security list already allows all intra-VCN traffic).

## Notes

- VMs get private IPs by default (`enable_public_ip = false`) — the Traefik child dials them in-VCN (`ipMode=private`).
- Boot image defaults to the latest Canonical Ubuntu 24.04 platform image (the cloud-init installs docker via apt; Oracle Linux doesn't ship it).
- Per-instance IP-mode override: the `traefik.oci.ipmode` tag.

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
| <a name="module_compute"></a> [compute](#module\_compute) | ../../../compute/oracle/vm | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | OCID of the compartment the VMs are created in | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | OCID of the existing subnet the VM VNICs join (e.g. compute/oracle/oke's nodes\_subnet\_id, so the Traefik child reaches these VMs in-VCN) | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to OCI VMs. Each app can have multiple replicas. Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` become dotted-key traefik.* freeform tags. | `any` | `{}` | no |
| <a name="input_availability_domain"></a> [availability\_domain](#input\_availability\_domain) | Availability domain the VMs are placed in. Empty = the compartment's first AD (same pick as compute/oracle/oke). | `string` | `""` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common freeform tags to apply to all VMs | `map(string)` | `{}` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Assign a public IP to each VM (requires a public subnet). Off by default — the Traefik child dials private IPs (ipMode=private). | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_memory_in_gbs"></a> [memory\_in\_gbs](#input\_memory\_in\_gbs) | Memory (GB) per VM | `number` | `2` | no |
| <a name="input_nsg_ids"></a> [nsg\_ids](#input\_nsg\_ids) | Network security group OCIDs to attach to the VM VNICs. Also what the oci provider's opt-in nsgPortDiscovery reads ports from. | `list(string)` | `[]` | no |
| <a name="input_ocpus"></a> [ocpus](#input\_ocpus) | OCPUs per VM (1 OCPU = 2 vCPUs on E4.Flex) | `number` | `1` | no |
| <a name="input_shape"></a> [shape](#input\_shape) | Compute shape for all echo servers (flex shapes are sized by ocpus/memory\_in\_gbs) | `string` | `"VM.Standard.E4.Flex"` | no |
| <a name="input_vm_image_ocid"></a> [vm\_image\_ocid](#input\_vm\_image\_ocid) | Boot image OCID. Empty = latest Canonical Ubuntu 24.04 platform image for the shape. | `string` | `""` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each VM. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server VMs with their details |
<!-- END_TF_DOCS -->
