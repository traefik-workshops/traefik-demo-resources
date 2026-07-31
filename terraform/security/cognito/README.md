# security/cognito

Provisions an AWS Cognito User Pool, a domain, an App Client, and a set of demo users.

## Example usage

```hcl
module "cognito" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/security/cognito?ref=v5.3.0"

  # Cognito hosted domains are GLOBALLY unique per region — give every stack in
  # an account/region its own name (the default is "traefik-demo").
  name = "my-demo"

  users         = ["admin", "support"]
  redirect_uris = ["https://demo.traefik.ai/callback"]
}
```

## Prerequisites

- AWS credentials with Cognito permissions.

## Notes

- `name` names the user pool and app client, and (underscores → hyphens) the **hosted domain**. Domains are **globally unique per region**: two deployments sharing a `name` in the same account/region fail on the domain — that's why `demos/aws-unified-ingress` sets its own `name` while `demos/oidc-portal` keeps the default.
- AWS forbids the substrings `aws`, `amazon` and `cognito` in hosted-domain prefixes (a precondition catches this) — set `domain_prefix` to override the name-derived default when your `name` contains one.
- `enable_unique_domain` (default **off**) appends a `random_id` suffix to the domain for guaranteed uniqueness. Flipping it on an existing deployment **replaces the domain** — hence off by default.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0, < 7.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cognito_user.users](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user) | resource |
| [aws_cognito_user_group.groups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_group) | resource |
| [aws_cognito_user_in_group.user_group_assignments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_in_group) | resource |
| [aws_cognito_user_pool.pool](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool) | resource |
| [aws_cognito_user_pool_client.client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_domain.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_domain) | resource |
| [random_id.domain](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_domain_prefix"></a> [domain\_prefix](#input\_domain\_prefix) | Explicit Cognito hosted-domain prefix. Empty (the default) derives it from name (underscores → hyphens). Needed when name contains a substring AWS forbids in domain prefixes ("aws", "amazon", "cognito"). | `string` | `""` | no |
| <a name="input_enable_unique_domain"></a> [enable\_unique\_domain](#input\_enable\_unique\_domain) | Append a random suffix to the hosted-domain prefix so same-named stacks can't collide on the region-global domain namespace. Default off — the domain is exactly the name-derived prefix; flipping this on an EXISTING deployment replaces the domain. | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the user pool and app client, and (via domain\_prefix's default, underscores → hyphens) the hosted domain. Cognito domains are GLOBALLY unique per region, so give every stack deployed into the same AWS account/region its own name — two deployments sharing the default collide on the domain. | `string` | `"traefik-demo"` | no |
| <a name="input_redirect_uris"></a> [redirect\_uris](#input\_redirect\_uris) | Allowed callback URL for the authentication flow | `list(string)` | `[]` | no |
| <a name="input_user_password"></a> [user\_password](#input\_user\_password) | Initial password assigned to every created Cognito user. Demo default — override for anything beyond ephemeral PoCs. | `string` | `"topsecretpassword"` | no |
| <a name="input_users"></a> [users](#input\_users) | List of Cognito users to be created | `list(string)` | <pre>[<br/>  "admin",<br/>  "support"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_client_id"></a> [app\_client\_id](#output\_app\_client\_id) | The ID of the Cognito App Client |
| <a name="output_app_client_secret"></a> [app\_client\_secret](#output\_app\_client\_secret) | The client secret of the Cognito App Client |
| <a name="output_user_pool_domain"></a> [user\_pool\_domain](#output\_user\_pool\_domain) | The endpoint name of the Cognito User Pool |
| <a name="output_user_pool_id"></a> [user\_pool\_id](#output\_user\_pool\_id) | The ID of the Cognito User Pool |
| <a name="output_users"></a> [users](#output\_users) | List of created users |
<!-- END_TF_DOCS -->
