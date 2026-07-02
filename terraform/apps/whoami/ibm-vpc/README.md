# apps/whoami/ibm-vpc

Provisions Traefik `whoami` (default image: the OTel-instrumented fork `docker.io/zalbiraw/whoami`) on IBM Cloud VPC virtual server instances — the IBM sibling of `apps/whoami/ec2` / `apps/whoami/alibaba-ecs`. Reuses `apps/whoami/cloud-init` (docker-run systemd unit).

> **New provider**: this is one of the repo's first IBM Cloud modules and introduces the `IBM-Cloud/ibm` Terraform provider (pinned `~> 1.89`).

## The discovery model is DIFFERENT from every other VM sibling

IBM Cloud user tags are **flat strings** with a restricted character set — they cannot carry dotted `traefik.*` configuration the way EC2/Azure/OCI/Alibaba tags do. The Traefik Hub `ibmVPC` provider (`traefik/ibm-vpc`) therefore works Nutanix-style:

1. Routers, services and middlewares live in a **base configuration file** on the gateway (the Traefik child's `base_config_content`).
2. Each instance carries exactly **one assignment tag** — `<service_name_tag_key>:<service_name>` (default key `traefik-service-name`) — and the provider fills that service's `servers` with the tagged instances' IPs, resolved via a single Global Search query.

So in this module, each app's `service_name` (default: the app key) is the **only** traefik-facing input. There is no `tags` map, no per-instance router/rule/port config. Keep service names lowercase — IBM stores user tags lowercased.

## Example usage

```hcl
module "whoami_ibm_vpc" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/apps/whoami/ibm-vpc?ref=v4.3.0"

  subnet_id          = module.vpc.subnet_id
  security_group_ids = module.vpc.security_group_ids

  apps = {
    whoami = {
      replicas     = 2
      port         = 80
      name         = "whoami-ibm-vpc" # body shows `Name: whoami-ibm-vpc`
      service_name = "whoami"         # -> instance tag "traefik-service-name:whoami"
    }
  }
}
```

The matching router/service pair lives in the Traefik child's base configuration file (see `traefik/ibm-vpc`'s `base_config_content` example).

## Prerequisites

- IBM Cloud API key with VPC permissions; the region comes from the configured `ibm` provider.
- An existing subnet + security group to join (e.g. `compute/ibm/vpc`'s). The subnet needs a public gateway for docker pulls (`compute/ibm/vpc` attaches one per zone); the security group must allow the app port in and egress out (IBM security groups deny both directions by default).

## Notes

- whoami needs no cloud API access, so the instances carry no trusted profile / API key.
- `enable_floating_ip` is inbound-only convenience — egress rides the subnet's public gateway either way.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_ibm"></a> [ibm](#requirement\_ibm) | ~> 1.89 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_ibm"></a> [ibm](#provider\_ibm) | ~> 1.89 |

## Resources

| Name | Type |
|------|------|
| [ibm_is_floating_ip.whoami](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_floating_ip) | resource |
| [ibm_is_instance.whoami](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/is_instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs to attach to the instances (e.g. compute/ibm/vpc's security\_group\_ids — IBM security groups deny both directions by default, so attach one that allows the app port in and image pulls out) | `list(string)` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the existing subnet the instances join (e.g. compute/ibm/vpc's subnet\_id, so the Traefik child reaches these VMs in-VPC). The zone and VPC derive from it. | `string` | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy to VPC instances. Each app can have multiple replicas: { name = { replicas, port, name, environment, service\_name } }. Optional `environment` (map) is merged over the module-level `environment` into the container. UNLIKE the ec2/alibaba-ecs siblings there are NO dotted traefik.* tags — `service_name` (default: the app key; keep it lowercase, IBM lowercases tags) becomes the instance user tag `<service_name_tag_key>:<service_name>`, assigning the instance to that service in the ibmVPC provider's base configuration file. | `any` | `{}` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common user tags (flat strings) to apply to all instances | `list(string)` | `[]` | no |
| <a name="input_enable_floating_ip"></a> [enable\_floating\_ip](#input\_enable\_floating\_ip) | Attach a floating IP to each instance (inbound access only). Off by default — the Traefik child dials private IPs (ipMode=private), and image pulls ride the subnet's public gateway. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_image_id"></a> [image\_id](#input\_image\_id) | Boot image ID. Empty = latest stock Ubuntu 24.04 amd64 image. | `string` | `""` | no |
| <a name="input_instance_profile"></a> [instance\_profile](#input\_instance\_profile) | VSI profile for all echo servers (default: 2 vCPU / 4 GB — the smallest VPC gen2 compute profile) | `string` | `"cx2-2x4"` | no |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource group ID the instances land in. Empty = the account's default resource group. | `string` | `""` | no |
| <a name="input_service_name_tag_key"></a> [service\_name\_tag\_key](#input\_service\_name\_tag\_key) | User-tag key assigning an instance to a base-configuration service (tag format <key>:<service>). Must match the ibmVPC provider's serviceNameTagKey. | `string` | `"traefik-service-name"` | no |
| <a name="input_ssh_key_ids"></a> [ssh\_key\_ids](#input\_ssh\_key\_ids) | IBM Cloud SSH key IDs to inject (debugging convenience — whoami itself needs none) | `list(string)` | `[]` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run on each instance. Untagged references get `:` + whoami\_version appended. | `string` | `"docker.io/zalbiraw/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all echo server instances with their details |
<!-- END_TF_DOCS -->
