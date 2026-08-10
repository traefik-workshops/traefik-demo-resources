# security/oci-instance-principal

Creates an OCI dynamic group and policy so instances in a compartment can authenticate as instance principals (no static API keys).

## Example usage

```hcl
module "oci_instance_principal" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/security/oci-instance-principal?ref=v6.0.0"

  compartment_id = var.compartment_id
}
```

## Prerequisites

- OCI credentials with IAM (dynamic group + policy) permissions.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [null_resource.dynamic_group](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.policy](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | The OCID of the workload compartment whose instances the dynamic group matches. | `string` | n/a | yes |
| <a name="input_home_region"></a> [home\_region](#input\_home\_region) | Tenancy home region identifier (e.g. us-ashburn-1). OCI IAM writes only succeed against the home region, so the dynamic group + policy are created there via the OCI CLI. | `string` | n/a | yes |
| <a name="input_tenancy_id"></a> [tenancy\_id](#input\_tenancy\_id) | Tenancy OCID (root compartment). OCI dynamic groups and their policies are tenancy-level and MUST live in the root compartment. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
