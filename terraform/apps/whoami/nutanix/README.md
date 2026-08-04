# apps/whoami/nutanix

Provisions a Traefik `whoami` VM on Nutanix AHV via `compute/nutanix/vm`, with cloud-init (docker-run systemd unit; default image: the OTel-instrumented fork `ghcr.io/zalbiraw/whoami`) and Prism Central category-based service discovery.

## Example usage

```hcl
module "whoami_nutanix" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/nutanix?ref=v5.4.1"

  vm_name     = "whoami-01"
  cluster_id  = var.nutanix_cluster_uuid
  subnet_uuid = var.subnet_uuid
  image_id    = module.whoami_image.id

  # OTel config for the instrumented fork — passed to the container via docker -e.
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_SERVICE_NAME           = "whoami-nutanix"
  }
}
```

## Prerequisites

- A reachable Nutanix Prism Central endpoint and credentials.
- A pre-built whoami image (see `apps/whoami/nutanix/image_builder`).

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
| <a name="input_cluster_id"></a> [cluster\_id](#input\_cluster\_id) | UUID of the Nutanix Cluster | `string` | n/a | yes |
| <a name="input_image_id"></a> [image\_id](#input\_image\_id) | UUID of the Image to use | `string` | n/a | yes |
| <a name="input_subnet_uuid"></a> [subnet\_uuid](#input\_subnet\_uuid) | UUID of the Subnet | `string` | n/a | yes |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Name of the VM | `string` | n/a | yes |
| <a name="input_arch"></a> [arch](#input\_arch) | Architecture of the VM | `string` | `"amd64"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to the whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. | `map(string)` | `{}` | no |
| <a name="input_load_balancer_strategy"></a> [load\_balancer\_strategy](#input\_load\_balancer\_strategy) | Load balancer strategy for Nutanix Prism Central discovery (TraefikLoadBalancerStrategy category) | `string` | `""` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Service name for Nutanix Prism Central discovery (TraefikServiceName category) | `string` | `"whoami"` | no |
| <a name="input_service_port"></a> [service\_port](#input\_service\_port) | Service port for Nutanix Prism Central discovery (TraefikServicePort category) | `number` | `8080` | no |
| <a name="input_static_ip"></a> [static\_ip](#input\_static\_ip) | Static IP for the whoami VM NIC. Empty means DHCP. | `string` | `""` | no |
| <a name="input_vm_memory_mib"></a> [vm\_memory\_mib](#input\_vm\_memory\_mib) | Memory size in MiB | `number` | `1024` | no |
| <a name="input_vm_num_sockets"></a> [vm\_num\_sockets](#input\_vm\_num\_sockets) | Number of sockets | `number` | `1` | no |
| <a name="input_vm_num_vcpus_per_socket"></a> [vm\_num\_vcpus\_per\_socket](#input\_vm\_num\_vcpus\_per\_socket) | Number of vCPUs per socket | `number` | `1` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on the VM. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/zalbiraw/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | Ip address. |
<!-- END_TF_DOCS -->
