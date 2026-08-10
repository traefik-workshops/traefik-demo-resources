# apps/whoami/gce

Provisions one or more Traefik `whoami` instances on GCE VMs — the GCP sibling of `apps/whoami/ec2` and `apps/whoami/azure-vm`, reusing the `whoami/cloud-init` template (docker-run systemd unit; default image: the OTel-instrumented fork `ghcr.io/traefik-workshops/whoami`). The `apps` map reads almost identically to the EC2/Azure modules — with one deliberate difference:

## The machine carries only a service name

GCE cannot carry routing intent on the machine: label keys and values are limited to lowercase `[a-z0-9_-]` (63 chars max), so neither dotted `traefik.*` keys nor rule syntax fit. Under the Hub `gce` provider's contract a VM carries **only a service name** — the value of one plain GCE label (the provider's `serviceNameLabel`, default `traefik-service`), set through the app's `labels` map:

```hcl
labels = { traefik-service = "whoami" }
```

The label value is single-valued (no comma lists), so **one VM backs one service**; VMs sharing a value merge into one load balancer. Everything ABOUT the service — port, scheme, LB strategy, health checks, routers — lives in the base configuration the gateway's gce provider loads over `configEndpoint` (GitOps) or `filename`, never on the VM.

## Example usage

```hcl
module "whoami_gce" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/gce?ref=v6.1.1"

  zone    = "us-central1-a"
  network = module.gke.network # or "default"

  # OTel config for the instrumented fork — passed to every container via docker -e
  # (per-app `environment` entries win on collision).
  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://otel-collector.internal:4318"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    OTEL_SERVICE_NAME           = "whoami-gce"
  }

  apps = {
    whoami = {
      replicas = 2
      port     = 80
      name     = "whoami-gce" # body shows `Name: whoami-gce`
      labels = {
        # The ONLY workload config on the VM: the service these VMs back. The
        # service itself (port/strategy/routers) is defined in the gateway's
        # base configuration.
        traefik-service = "whoami"
      }
    }
  }
}
```

## Prerequisites

- GCP credentials with Compute permissions; the Compute Engine API enabled.
- A joinable VPC network. The default (`network = "default"`) is the project's default network — the same one `compute/gcp/gke` clusters sit on (see its `network` output), so the Traefik child reaches these VMs privately.

## Notes

- VMs get private IPs by default (`enable_public_ip = false`) — the Traefik child dials them in-network (`ipMode=private`).
- `enable_firewall` (default on) opens the app ports intra-network via a tag-targeted rule (mirrors `compute/azure/vnet`'s NSG); the default network's `default-allow-internal` usually covers this already, so it's safe to disable there.

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
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to GCE VMs. Each app can have multiple replicas. Same shape as apps/whoami/ec2 EXCEPT the workload config: instead of dotted traefik.* tags, an app's `labels` map carries plain GCE labels — including the service-name label the Hub gce provider reads (e.g. `traefik-service = "whoami"`), whose value names the ONE service the app's VMs back. Routing intent lives in the gateway's base configuration, never here. { name = { replicas, port, name, environment, labels } } — optional `environment` (map) is merged over the module-level `environment` into the container. | `any` | `{}` | no |
| <a name="input_common_labels"></a> [common\_labels](#input\_common\_labels) | Common GCE labels to apply to all VMs. Per-app `labels` win on collision; keep the service-name label per-app so each app names its own service. | `map(string)` | `{}` | no |
| <a name="input_enable_firewall"></a> [enable\_firewall](#input\_enable\_firewall) | Create a firewall rule opening the app ports intra-network to these VMs (mirrors compute/azure/vnet's NSG). Disable when the network already allows it (e.g. default network's default-allow-internal). | `bool` | `true` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Attach an ephemeral public IP to each VM. Off by default — the Traefik child dials private IPs (ipMode=private). | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_firewall_source_ranges"></a> [firewall\_source\_ranges](#input\_firewall\_source\_ranges) | Source CIDR ranges allowed by the firewall rule. Default covers the default network (10.128.0.0/9) and typical GKE node/pod ranges. | `list(string)` | <pre>[<br/>  "10.0.0.0/8"<br/>]</pre> | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | GCE machine type for all echo servers | `string` | `"e2-micro"` | no |
| <a name="input_network"></a> [network](#input\_network) | VPC network the VMs join. Defaults to the project's default network — the same one compute/gcp/gke clusters sit on (see its `network` output), so the Traefik child reaches these VMs privately. | `string` | `"default"` | no |
| <a name="input_network_tags"></a> [network\_tags](#input\_network\_tags) | Network tags applied to the VMs (firewall targeting). The firewall rule name is derived from the first tag. | `list(string)` | <pre>[<br/>  "whoami"<br/>]</pre> | no |
| <a name="input_subnetwork"></a> [subnetwork](#input\_subnetwork) | Subnetwork the VMs join. Empty = let GCP pick the network's subnet in the zone's region (works on auto-mode networks like `default`). | `string` | `""` | no |
| <a name="input_vm_image"></a> [vm\_image](#input\_vm\_image) | Boot disk image (family or self link) | `string` | `"ubuntu-os-cloud/ubuntu-2404-lts-amd64"` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each VM. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |
| <a name="input_zone"></a> [zone](#input\_zone) | GCE zone the VMs are created in | `string` | `"us-central1-a"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server VMs with their details |
<!-- END_TF_DOCS -->
