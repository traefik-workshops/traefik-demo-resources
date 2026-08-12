# compute/oracle/ci

Provisions a fleet of OCI Container Instances from an `instances` map (one
`oci_container_instances_container_instance` per entry) and resolves each
instance's private VNIC IP. The per-instance container definition (image,
command, environment, health check, mounts) and CONFIGFILE volumes are passed in
as opaque structured payloads — this module owns only the infrastructure
resource, no role-specific (Traefik Hub / whoami) logic.

Shared by `traefik/oci-ci` (one instance — the multicluster child) and
`apps/whoami/oci-ci` (N instances — the discovered workloads).

## Example usage

```hcl
module "ci" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/oracle/ci?ref=v6.3.0"

  compartment_id = var.compartment_id
  subnet_id      = var.subnet_id

  instances = {
    "whoami-1" = {
      display_name = "whoami-1"
      containers = [{
        display_name = "whoami"
        image_url    = "ghcr.io/traefik-workshops/whoami:latest"
        environment_variables = {
          WHOAMI_NAME = "whoami-1"
        }
        health_checks = {
          health_check_type = "TCP"
          port              = 80
        }
      }]
    }
  }
}
```

## Prerequisites

- OCI credentials with Container Instances / networking permissions.
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_oci"></a> [oci](#provider\_oci) | ~> 7.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [oci_container_instances_container_instance.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/container_instances_container_instance) | resource |
| [oci_core_vnic.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/core_vnic) | data source |
| [oci_identity_availability_domains.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_availability_domains) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | OCID of the compartment the container instances are created in. | `string` | n/a | yes |
| <a name="input_instances"></a> [instances](#input\_instances) | Map of container instances to create, keyed by instance name (the key becomes<br/>the for\_each key and the outputs' key). Each entry carries the already-rendered,<br/>OPAQUE container + volume payload — this module renders it verbatim and does not<br/>interpret its contents (no whoami/traefik-hub logic here).<br/><br/>- display\_name  : the instance's display name.<br/>- freeform\_tags : freeform tags for the instance (the discovered workload config<br/>                  / discovery tags — the module passes them through untouched).<br/>- private\_ip    : optional static private IP for the VNIC (null = provider-assigned).<br/>- containers    : list of container blocks (image\_url, optional command/arguments/<br/>                  environment\_variables, optional TCP health check, volume mounts).<br/>- volumes       : list of CONFIGFILE volume blocks (already base64-encoded configs). | <pre>map(object({<br/>    display_name  = string<br/>    freeform_tags = optional(map(string), {})<br/>    private_ip    = optional(string, null)<br/>    containers = list(object({<br/>      display_name          = string<br/>      image_url             = string<br/>      command               = optional(list(string), null)<br/>      arguments             = optional(list(string), null)<br/>      environment_variables = optional(map(string), null)<br/>      health_checks = optional(object({<br/>        health_check_type = string<br/>        port              = number<br/>      }), null)<br/>      volume_mounts = optional(list(object({<br/>        volume_name = string<br/>        mount_path  = string<br/>      })), [])<br/>    }))<br/>    volumes = optional(list(object({<br/>      name        = string<br/>      volume_type = string<br/>      configs = list(object({<br/>        file_name = string<br/>        data      = string<br/>      }))<br/>    })), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | OCID of the existing subnet each container-instance VNIC joins. | `string` | n/a | yes |
| <a name="input_availability_domain"></a> [availability\_domain](#input\_availability\_domain) | Availability domain the container instances are placed in. Empty = the compartment's first AD. | `string` | `""` | no |
| <a name="input_container_memory_in_gbs"></a> [container\_memory\_in\_gbs](#input\_container\_memory\_in\_gbs) | Memory (GB) for each container instance. | `number` | `4` | no |
| <a name="input_container_ocpus"></a> [container\_ocpus](#input\_container\_ocpus) | OCPUs for each container instance (1 OCPU = 2 vCPUs on E4.Flex). | `number` | `1` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Assign a public IP to each container-instance VNIC (is\_public\_ip\_assigned). | `bool` | `false` | no |
| <a name="input_nsg_ids"></a> [nsg\_ids](#input\_nsg\_ids) | Network security group OCIDs to attach to each container-instance VNIC. | `list(string)` | `[]` | no |
| <a name="input_shape"></a> [shape](#input\_shape) | Container instance shape (flex shapes are sized by container\_ocpus/container\_memory\_in\_gbs). | `string` | `"CI.Standard.E4.Flex"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all container instances with their details (keyed by the var.instances key). |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance key to private VNIC IP address. |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance key to public VNIC IP address (null unless enable\_public\_ip). |
<!-- END_TF_DOCS -->
