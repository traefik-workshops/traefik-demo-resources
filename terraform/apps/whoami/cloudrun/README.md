# apps/whoami/cloudrun

Provisions Traefik `whoami` as Cloud Run v2 services — the serverless GCP sibling of `apps/whoami/ecs` and `apps/whoami/aci`. Each service's **`traefik.*` annotations** (dotted keys) are the workload config a Traefik Hub `cloudRun` provider discovers; **labels** (dotless) feed the provider's `constraints` only. Cloud Run is URL-mode: the provider routes to the service's HTTPS URI — there is no IP/port discovery.

Cloud Run can't pull `docker.io` images directly, so the module creates an Artifact Registry **remote repository** (a Docker Hub pull-through mirror) and runs `traefik/whoami` through it. Override with `image` (any AR/GCR path) and set `enable_registry_mirror = false` to skip the mirror.

## Optional function (`enable_function`)

`enable_function = true` also deploys a tiny whoami-ish HTTP function from **inline source** via Cloud Run's `build_config` — the current-generation Cloud Functions path (a gen2 Cloud Function IS a Cloud Run service, discovered identically by the provider). `archive_file` zips the inline Node.js source, a GCS bucket holds it, a dedicated build SA runs the Cloud Build, and the resulting service takes `function_annotations` through the **same annotations pathway** as the plain services.

Why not `google_cloudfunctions2_function`? Its schema exposes no way to set annotations on the underlying Run service — the annotation passthrough is not expressible there, so this module uses the `build_config` route instead.

## Example usage

```hcl
module "whoami_cloudrun" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/apps/whoami/cloudrun?ref=v4.3.0"

  location = "us-central1"

  apps = {
    whoami-cloudrun = {
      port = 80
      name = "whoami-cloudrun" # body shows `Name: whoami-cloudrun`
      annotations = {
        "traefik.enable" = "true"
      }
      labels = {
        env = "demo" # dotless — constraints matching only
      }
    }
  }

  # Optionally a gen2 Cloud Function through the same annotations pathway.
  enable_function      = true
  function_annotations = { "traefik.enable" = "true" }
}
```

## Prerequisites

- GCP credentials; APIs enabled: `run.googleapis.com`, `artifactregistry.googleapis.com` — plus `cloudbuild.googleapis.com` and `storage.googleapis.com` when `enable_function = true`.
- `enable_viewer_role`-style IAM-grant rights are needed for the function's build SA bindings.

## Notes

- Unauthenticated invocation is ON by default (`enable_unauthenticated`) — demo-grade; the Traefik child dials the public service URL.
- `min_instances = 0` (scale to zero) by default; first request after idle pays a cold start.
- `archive_file` writes `function-source.zip` into the module directory at plan time (gitignored in consumers' module caches).

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | ~> 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | ~> 2.0 |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |

## Resources

| Name | Type |
|------|------|
| [google_artifact_registry_repository.function_images](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository.mirror](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository_iam_member.function_build_image_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_cloud_run_v2_service.function](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) | resource |
| [google_cloud_run_v2_service.whoami](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) | resource |
| [google_cloud_run_v2_service_iam_member.function_invoker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service_iam_member) | resource |
| [google_cloud_run_v2_service_iam_member.invoker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service_iam_member) | resource |
| [google_project_iam_member.function_build_act_as](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.function_build_logs_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_service_account.function_build](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_storage_bucket.function_source](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.function_build_source_reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_object.function_source](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_object) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_apps"></a> [apps](#input\_apps) | Map of Cloud Run services to deploy. Workload config is `annotations` (dotted traefik.* keys, the cloudRun provider's config source); optional `labels` (dotless) feed provider constraints only. No replicas — Cloud Run scales via min/max instances. { name = { port, name, annotations, labels } }. | `any` | `{}` | no |
| <a name="input_common_annotations"></a> [common\_annotations](#input\_common\_annotations) | Annotations applied to every service (dotted traefik.* keys allowed — provider workload config) | `map(string)` | `{}` | no |
| <a name="input_common_labels"></a> [common\_labels](#input\_common\_labels) | Labels applied to every service (dotless — provider constraints only) | `map(string)` | `{}` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Cloud Run v2 deletion protection. Off — demos are torn down per-run. | `bool` | `false` | no |
| <a name="input_enable_function"></a> [enable\_function](#input\_enable\_function) | Also deploy a whoami-ish HTTP function from inline source via Cloud Run's build\_config (the gen2 Cloud Functions path — the built function IS a Cloud Run service, discovered via the same annotations pathway). Requires the Cloud Build API. | `bool` | `false` | no |
| <a name="input_enable_registry_mirror"></a> [enable\_registry\_mirror](#input\_enable\_registry\_mirror) | Create an Artifact Registry REMOTE repository mirroring Docker Hub (how traefik/whoami becomes pullable by Cloud Run). Disable only when `image` is set. | `bool` | `true` | no |
| <a name="input_enable_unauthenticated"></a> [enable\_unauthenticated](#input\_enable\_unauthenticated) | Grant roles/run.invoker to allUsers on every service (demo-grade; the Traefik child dials the service URL unauthenticated) | `bool` | `true` | no |
| <a name="input_function_annotations"></a> [function\_annotations](#input\_function\_annotations) | Annotations for the function's Cloud Run service (dotted traefik.* keys — same pathway as the plain services) | `map(string)` | `{}` | no |
| <a name="input_function_labels"></a> [function\_labels](#input\_function\_labels) | Labels for the function's Cloud Run service (dotless — provider constraints only) | `map(string)` | `{}` | no |
| <a name="input_function_name"></a> [function\_name](#input\_function\_name) | Name of the function's Cloud Run service (also prefixes its source bucket, image repository, and build SA) | `string` | `"whoami-fn"` | no |
| <a name="input_image"></a> [image](#input\_image) | Full image reference override. Empty = pull traefik/whoami through the module's Docker Hub mirror (requires enable\_registry\_mirror). Must be an Artifact Registry / GCR path — Cloud Run can't pull docker.io directly. | `string` | `""` | no |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | Cloud Run ingress setting (INGRESS\_TRAFFIC\_ALL, INGRESS\_TRAFFIC\_INTERNAL\_ONLY, INGRESS\_TRAFFIC\_INTERNAL\_LOAD\_BALANCER). The Traefik child dials the public service URL, so ALL is the demo default. | `string` | `"INGRESS_TRAFFIC_ALL"` | no |
| <a name="input_location"></a> [location](#input\_location) | Cloud Run region (also used for the Artifact Registry repositories and the function source bucket) | `string` | `"us-central1"` | no |
| <a name="input_max_instances"></a> [max\_instances](#input\_max\_instances) | Maximum instance count per service | `number` | `2` | no |
| <a name="input_min_instances"></a> [min\_instances](#input\_min\_instances) | Minimum instance count per service (0 = scale to zero) | `number` | `0` | no |
| <a name="input_mirror_repository_id"></a> [mirror\_repository\_id](#input\_mirror\_repository\_id) | Repository ID for the Docker Hub mirror (unique per project+location) | `string` | `"dockerhub-mirror"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | The traefik/whoami image tag to run — they carry a `v` prefix (e.g. v1.11.0). | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_function_service_name"></a> [function\_service\_name](#output\_function\_service\_name) | Name of the function's Cloud Run service (empty when enable\_function = false) |
| <a name="output_function_uri"></a> [function\_uri](#output\_function\_uri) | HTTPS URI of the function's Cloud Run service (empty when enable\_function = false) |
| <a name="output_services"></a> [services](#output\_services) | Map of all echo Cloud Run services with their details (uri is what the cloudRun provider routes to) |
<!-- END_TF_DOCS -->
