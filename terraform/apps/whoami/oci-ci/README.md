# apps/whoami/oci-ci

Provisions Traefik `whoami` (default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`) as OCI Container Instances — the OCI sibling of `apps/whoami/aci`. Each app replica is one container instance with a private VNIC IP; the `apps` map reads identically to `apps/whoami/ec2`.

Each instance's freeform tags (dotted `traefik.*` keys, exactly like ACI tags / ECS docker labels) are the workload config a Traefik Hub `ociContainerInstances` provider (`traefik/oci-ci`) discovers. Without `nsgPortDiscovery`, the provider falls back to the instance's lowest declared container port — OCI has no "published port" field, so this module declares it via the container's TCP health check (from `apps.<name>.port`, default 80), and a container instance serving on port 80 needs no port tag.

## Example usage

```hcl
module "whoami_oci_ci" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/oci-ci?ref=v6.1.1"

  compartment_id = var.compartment_id
  subnet_id      = module.oke.nodes_subnet_id

  # OTel config for the instrumented fork — added to every container's env
  # (per-app `environment` entries win on collision).
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_SERVICE_NAME           = "whoami-oci-ci"
  }

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-oci-ci" # body shows `Name: whoami-oci-ci`
      tags = {
        "traefik.enable" = "true"
        # No port tag needed: the declared port 80 (TCP health check) is the fallback.
      }
    }
  }
}
```

## Prerequisites

- OCI credentials with Container Instances/Network permissions and an existing compartment.
- An existing subnet to join (e.g. `compute/oracle/oke`'s `nodes_subnet_id` — its security list already allows all intra-VCN traffic).

## Notes

- Container instances get private VNIC IPs only — the Traefik child dials them in-VCN (`ipMode=private`).
- Per-instance IP-mode override: the `traefik.ocici.ipmode` tag.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |

## Providers

No providers.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | OCID of the compartment the container instances are created in | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | OCID of the existing subnet the container instance VNICs join (e.g. compute/oracle/oke's nodes\_subnet\_id, so the Traefik child reaches them in-VCN) | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to OCI Container Instances. Each app can have multiple replicas (one container instance each). Same shape as apps/whoami/ec2: { name = { replicas, port, name, environment, tags } } — optional `environment` (map) is merged over the module-level `environment` into the container; `tags` become dotted-key traefik.* freeform tags. | `any` | `{}` | no |
| <a name="input_availability_domain"></a> [availability\_domain](#input\_availability\_domain) | Availability domain the container instances are placed in. Empty = the compartment's first AD (same pick as compute/oracle/oke). | `string` | `""` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common freeform tags to apply to all container instances | `map(string)` | `{}` | no |
| <a name="input_container_memory_in_gbs"></a> [container\_memory\_in\_gbs](#input\_container\_memory\_in\_gbs) | Memory (GB) per container instance | `number` | `2` | no |
| <a name="input_container_ocpus"></a> [container\_ocpus](#input\_container\_ocpus) | OCPUs per container instance (1 OCPU = 2 vCPUs on E4.Flex) | `number` | `1` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables added to every whoami container, e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_nsg_ids"></a> [nsg\_ids](#input\_nsg\_ids) | Network security group OCIDs to attach to the container instance VNICs. Also what the ocici provider's opt-in nsgPortDiscovery reads ports from. | `list(string)` | `[]` | no |
| <a name="input_shape"></a> [shape](#input\_shape) | Container instance shape (flex shapes are sized by container\_ocpus/container\_memory\_in\_gbs) | `string` | `"CI.Standard.E4.Flex"` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image every container instance runs. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_instances"></a> [container\_instances](#output\_container\_instances) | Map of all echo server container instances with their details |
<!-- END_TF_DOCS -->
