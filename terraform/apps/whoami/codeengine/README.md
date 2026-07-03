# apps/whoami/codeengine

Provisions Traefik `whoami` (default image: the OTel-instrumented fork `docker.io/zalbiraw/whoami`) as IBM Cloud Code Engine apps — the serverless IBM sibling of `apps/whoami/cloudrun` / `apps/whoami/aci`. Creates the Code Engine project by default (`enable_project`); Code Engine pulls public Docker Hub images directly, so no registry mirror is needed.

> **New provider**: this is one of the repo's first IBM Cloud modules and introduces the `IBM-Cloud/ibm` Terraform provider (pinned `~> 1.89`).

## The traefik config surface is ONE env var: `TRAEFIK_LABELS`

Code Engine apps have no user-settable labels or annotations, so the Traefik Hub `ibmCodeEngine` provider reads its `traefik.*` labels from a single **`TRAEFIK_LABELS` env var carrying a JSON object** — set `traefik_labels` (module-level, or per-app inside `apps`; per-app wins on collision) and the module renders it. That buys the full label pipeline the dotted-tag siblings have:

- **`traefik.enable`** — opt-in/opt-out per app (pair `"traefik.enable" = "true"` with provider-side `exposedByDefault=false`).
- **User-named services** (`traefik.http.services.<name>.loadbalancer.*`) — and because the service is *named*, **multiple apps declaring the SAME service name are GROUPED into one load balancer** (one `<name>@ibmcodeengine` service, one server per app URL).
- **Middleware references** and the rest of the label vocabulary.

Apps without labels still route **config-less**: every ready app becomes a service targeting its HTTPS endpoint URL (URL-mode — no IP/port discovery), routed by the provider's `defaultRule`; `constraints` also match the synthesized pseudo-labels `name` and `visibility`.

`min_scale` defaults to 1 so the provider (which only routes READY apps) always sees a ready instance.

## Example usage

```hcl
module "whoami_codeengine" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/apps/whoami/codeengine?ref=v4.3.0"

  project_name = "traefik-demo"

  # Both apps declare the SAME user-named service -> the provider groups them
  # into one cewhoami@ibmcodeengine load balancer (two server URLs).
  traefik_labels = {
    "traefik.enable"                                             = "true"
    "traefik.http.services.cewhoami.loadbalancer.passhostheader" = "false"
  }

  apps = {
    whoami-1 = {
      port = 80
      name = "whoami-codeengine-1" # body shows `Name: whoami-codeengine-1`
    }
    whoami-2 = {
      port = 80
      name = "whoami-codeengine-2"
    }
  }
}

# The in-cluster Traefik child's provider flags:
#   --hub.providers.ibmCodeEngine=true
#   --hub.providers.ibmCodeEngine.region=<region>
#   --hub.providers.ibmCodeEngine.projectID=module.whoami_codeengine.project_id
#   --hub.providers.ibmCodeEngine.exposedByDefault=false   # traefik.enable opts apps in
# plus ONE credential — an IAM API key or (keyless, in-cluster) a trusted profile:
#   --hub.providers.ibmCodeEngine.apiKey=<ibm api key>
#   --hub.providers.ibmCodeEngine.trustedProfileID=<profile id>  # compute-resource-token flow
```

There is no `traefik/codeengine` child module — Code Engine can't host a raw `:9443` multicluster uplink, so demos run that child in-cluster (like GCP's Cloud Run setup) and point its `ibmCodeEngine` provider at this module's `project_id`.

## Prerequisites

- IBM Cloud API key with Code Engine permissions; the region comes from the configured `ibm` provider.

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
| [ibm_code_engine_app.whoami](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/code_engine_app) | resource |
| [ibm_code_engine_project.whoami](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/code_engine_project) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy as Code Engine apps: { name = { port, name, environment, traefik\_labels } }. Optional `environment` (map) is merged over the module-level `environment` into the container; optional `traefik_labels` (map) is merged over the module-level `traefik_labels` and rendered as the TRAEFIK\_LABELS env var the Hub ibmCodeEngine provider reads. Apps without labels route config-less by the provider's defaultRule. | `any` | `{}` | no |
| <a name="input_enable_project"></a> [enable\_project](#input\_enable\_project) | Create the Code Engine project in this module. Disable to deploy into an existing project via project\_id. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami container, e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_managed_domain_mappings"></a> [managed\_domain\_mappings](#input\_managed\_domain\_mappings) | Endpoint visibility of the apps: local\_public (public + project-local), local\_private (private network + project-local), or local (project-local only). The ibmCodeEngine provider surfaces it as the `visibility` pseudo-label for constraints. | `string` | `"local_public"` | no |
| <a name="input_max_scale"></a> [max\_scale](#input\_max\_scale) | Maximum instances per app | `number` | `1` | no |
| <a name="input_min_scale"></a> [min\_scale](#input\_min\_scale) | Minimum instances per app. Keep >= 1 so the ibmCodeEngine provider (which only routes READY apps) always sees a ready instance. | `number` | `1` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Existing Code Engine project ID (GUID) to deploy into. Required when enable\_project = false. | `string` | `""` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name of the Code Engine project the module creates (when enable\_project = true) | `string` | `"whoami"` | no |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource group ID the module-created project lands in. Empty = the account's default resource group. | `string` | `""` | no |
| <a name="input_traefik_labels"></a> [traefik\_labels](#input\_traefik\_labels) | traefik.* labels applied to every app, rendered as ONE env var — TRAEFIK\_LABELS, a JSON object — the Hub ibmCodeEngine provider parses. Full label pipeline: traefik.enable opt-in/opt-out, user-named services (traefik.http.services.<name>.loadbalancer.* — apps declaring the SAME service name are GROUPED into one load balancer), middleware references. Per-app `traefik_labels` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to run (Code Engine pulls public Docker Hub images directly). Untagged references get `:` + whoami\_version appended. | `string` | `"docker.io/zalbiraw/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_apps"></a> [apps](#output\_apps) | Map of all echo server apps with their details |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | Code Engine project ID (GUID) the apps run in — feed it to the ibmCodeEngine provider's projectID |
<!-- END_TF_DOCS -->
