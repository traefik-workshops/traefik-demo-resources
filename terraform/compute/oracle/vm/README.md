# compute/oracle/vm

Shared OCI Compute instance module. Provisions `replicas` `oci_core_instance`
VMs (keyed `<name>-<replica>`) from the latest Canonical Ubuntu 24.04 platform
image (or an explicit image OCID), with optional static private-IP pinning,
public IP, freeform tags, and opaque cloud-init user data. Both
`traefik/oci-vm` (the multicluster gateway, `replicas = 1`) and
`apps/whoami/oci-vm` (the echo backends, `replicas = N`) compose it.

Role-specific concerns stay in the callers: cloud-init rendering, the
instance-principal credential, dashboard self-registration tags, and NSG
creation. The module receives their results as opaque inputs.

## Example usage

```hcl
module "vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/oracle/vm?ref=v8.1.0"

  name           = "traefik"
  replicas       = 1
  compartment_id = var.compartment_id
  subnet_id      = var.subnet_id
  user_data      = local.rendered_cloud_init
}
```

## Prerequisites

- A reachable OCI tenancy and a compartment the caller's credentials can create
  instances in.
- A subnet OCID the VNIC(s) join.

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
| [oci_core_instance.vm](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_instance) | resource |
| [oci_core_images.ubuntu](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/core_images) | data source |
| [oci_identity_availability_domains.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_availability_domains) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | OCID of the compartment the instance(s) are created in (also the scope of the AD/image lookups). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Base name for the instance(s). Instances are keyed <name>-<replica> (name-1, name-2, …), matching compute/aws/ec2. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | OCID of the existing subnet the instance VNIC(s) join. | `string` | n/a | yes |
| <a name="input_availability_domain"></a> [availability\_domain](#input\_availability\_domain) | Availability domain the instance(s) are placed in. Empty = the compartment's first AD. | `string` | `""` | no |
| <a name="input_enable_public_ip"></a> [enable\_public\_ip](#input\_enable\_public\_ip) | Assign a public IP to each instance (requires a public subnet). | `bool` | `false` | no |
| <a name="input_freeform_tags"></a> [freeform\_tags](#input\_freeform\_tags) | Freeform tags applied to every instance (the callers merge their common/role-specific tags before passing them in). | `map(string)` | `{}` | no |
| <a name="input_memory_in_gbs"></a> [memory\_in\_gbs](#input\_memory\_in\_gbs) | Memory (GB) per instance. | `number` | `4` | no |
| <a name="input_nsg_ids"></a> [nsg\_ids](#input\_nsg\_ids) | Network security group OCIDs to attach to the VNIC(s). | `list(string)` | `[]` | no |
| <a name="input_ocpus"></a> [ocpus](#input\_ocpus) | OCPUs per instance (1 OCPU = 2 vCPUs on E4.Flex). | `number` | `1` | no |
| <a name="input_private_ips"></a> [private\_ips](#input\_private\_ips) | Fixed private IPs, one per replica index (instance idx N gets private\_ips[N]; extra instances fall back to DHCP). Each address must sit in subnet\_id's CIDR outside OCI's reserved first-2/last-1 hosts. Pinning makes the address plan-known AND stable across instance recreation. | `list(string)` | `[]` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Number of instances to create. The gateway calls with 1; whoami with N. | `number` | `1` | no |
| <a name="input_shape"></a> [shape](#input\_shape) | Compute shape (flex shapes are sized by ocpus/memory\_in\_gbs). | `string` | `"VM.Standard.E4.Flex"` | no |
| <a name="input_user_data"></a> [user\_data](#input\_user\_data) | Already-rendered cloud-init user data (opaque). Base64-encoded by the module before it lands in instance metadata. | `string` | `""` | no |
| <a name="input_vm_image_ocid"></a> [vm\_image\_ocid](#input\_vm\_image\_ocid) | Boot image OCID. Empty = latest Canonical Ubuntu 24.04 platform image for the shape. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of instance keys to their details (id, name, private\_ip, public\_ip). |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance keys to private IP addresses. |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance keys to public IP addresses (empty string when no public IP is assigned). |
<!-- END_TF_DOCS -->
