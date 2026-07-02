# whoami on Cloud Run — the serverless GCP sibling of apps/whoami/ecs and
# apps/whoami/aci. Each app is one Cloud Run v2 service; the service's
# `traefik.*` ANNOTATIONS (dotted keys) are the workload config a Traefik Hub
# cloudRun provider discovers (labels feed constraints only). Cloud Run is
# URL-mode: backends target the service's HTTPS URI — no IP/port discovery.
#
# Cloud Run can only pull from Artifact Registry / Container Registry, not
# Docker Hub — so the module creates an Artifact Registry REMOTE repository
# (pull-through Docker Hub mirror) and runs traefik/whoami through it.
#
# enable_function additionally deploys a whoami-ish HTTP function from inline
# source via `build_config` — the current-generation Cloud Run functions path.
# A gen2 Cloud Function IS a Cloud Run service, so the provider discovers it
# identically and the same annotations pathway applies (unlike
# google_cloudfunctions2_function, which cannot express service annotations).

data "google_project" "current" {}

locals {
  # A tag is a `:` in the LAST path segment (a registry host may carry a :port).
  image_last_segment = element(split("/", var.whoami_image), length(split("/", var.whoami_image)) - 1)
  whoami_image_ref   = length(regexall(":", local.image_last_segment)) > 0 ? var.whoami_image : "${var.whoami_image}:${var.whoami_version}"

  # The mirror is a Docker Hub remote repo, so the path inside it is the
  # docker.io repository path — strip the registry host if present.
  mirror_path  = trimprefix(trimprefix(local.whoami_image_ref, "registry-1.docker.io/"), "docker.io/")
  mirror_image = "${var.location}-docker.pkg.dev/${data.google_project.current.project_id}/${var.mirror_repository_id}/${local.mirror_path}"
  image        = var.image != "" ? var.image : local.mirror_image
}

resource "google_artifact_registry_repository" "mirror" {
  count = var.enable_registry_mirror ? 1 : 0

  location      = var.location
  repository_id = var.mirror_repository_id
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"
  description   = "Docker Hub pull-through mirror (Cloud Run can't pull docker.io directly)"

  remote_repository_config {
    docker_repository {
      public_repository = "DOCKER_HUB"
    }
  }
}

resource "google_cloud_run_v2_service" "whoami" {
  for_each = var.apps

  name                = each.key
  location            = var.location
  ingress             = var.ingress
  deletion_protection = var.deletion_protection

  # Dotted-key traefik.* annotations — the cloudRun provider's workload config
  # (exactly like ECS docker labels / ACI tags).
  annotations = merge(var.common_annotations, try(each.value.annotations, {}))
  # Labels (dotless) — provider constraints only.
  labels = merge(var.common_labels, try(each.value.labels, {}))

  template {
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = local.image

      # Cloud Run routes to container_port; WHOAMI_PORT_NUMBER makes whoami
      # actually bind it (whoami ignores Cloud Run's $PORT convention).
      ports {
        container_port = try(each.value.port, 80)
      }

      # WHOAMI_PORT_NUMBER makes whoami bind Cloud Run's routed port;
      # WHOAMI_NAME -> body shows `Name: <name>` (e.g. whoami-cloudrun).
      # Built-ins first so module/per-app `environment` wins on collision.
      dynamic "env" {
        for_each = merge(
          {
            WHOAMI_PORT_NUMBER = tostring(try(each.value.port, 80))
            WHOAMI_NAME        = try(each.value.name, each.key)
          },
          var.environment,
          try(each.value.environment, {}),
        )

        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  depends_on = [google_artifact_registry_repository.mirror]
}

# Demo-grade: anyone (incl. the Traefik child dialing the service URL) may invoke.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = var.enable_unauthenticated ? var.apps : {}

  name     = google_cloud_run_v2_service.whoami[each.key].name
  location = var.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Optional gen2-style Cloud Function (enable_function)
# =============================================================================
# Follows the provider's canonical "Cloudrunv2 Service Function" example:
# inline source zipped by archive_file, uploaded to GCS, built by Cloud Build
# with a dedicated build SA, deployed as a Cloud Run v2 service.
# =============================================================================

data "archive_file" "function" {
  count = var.enable_function ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/function-source.zip"

  source {
    filename = "package.json"
    content = jsonencode({
      name         = "whoami-function"
      main         = "index.js"
      dependencies = { "@google-cloud/functions-framework" = "^3.0.0" }
    })
  }

  source {
    filename = "index.js"
    content  = <<-EOT
      const functions = require('@google-cloud/functions-framework');
      const os = require('os');

      // whoami-ish HTTP echo: name, hostname, request line, headers.
      functions.http('whoami', (req, res) => {
        const lines = [
          `Name: $${process.env.WHOAMI_NAME || 'whoami-function'}`,
          `Hostname: $${os.hostname()}`,
          `RemoteAddr: $${req.ip}`,
          `$${req.method} $${req.originalUrl} HTTP/$${req.httpVersion}`,
        ];
        for (const [key, value] of Object.entries(req.headers)) {
          lines.push(`$${key}: $${value}`);
        }
        res.set('Content-Type', 'text/plain').send(lines.join('\n') + '\n');
      });
    EOT
  }
}

resource "google_storage_bucket" "function_source" {
  count = var.enable_function ? 1 : 0

  # Bucket names are globally unique — prefix with the project id.
  name                        = "${data.google_project.current.project_id}-${var.function_name}-source"
  location                    = var.location
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket_object" "function_source" {
  count = var.enable_function ? 1 : 0

  # Content-addressed name so a source change uploads a new object and
  # triggers a rebuild.
  name   = "function-source-${data.archive_file.function[0].output_md5}.zip"
  bucket = google_storage_bucket.function_source[0].name
  source = data.archive_file.function[0].output_path
}

# Standard (writable) repository for the built function image — the Docker Hub
# mirror above is REMOTE mode and can't be pushed to.
resource "google_artifact_registry_repository" "function_images" {
  count = var.enable_function ? 1 : 0

  location      = var.location
  repository_id = "${var.function_name}-images"
  format        = "DOCKER"
  description   = "Built images for the ${var.function_name} Cloud Run function"
}

resource "google_service_account" "function_build" {
  count = var.enable_function ? 1 : 0

  account_id   = "${var.function_name}-build"
  display_name = "Cloud Build SA for the ${var.function_name} function"
}

resource "google_project_iam_member" "function_build_act_as" {
  count = var.enable_function ? 1 : 0

  project = data.google_project.current.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.function_build[0].email}"
}

resource "google_project_iam_member" "function_build_logs_writer" {
  count = var.enable_function ? 1 : 0

  project = data.google_project.current.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_build[0].email}"
}

resource "google_storage_bucket_iam_member" "function_build_source_reader" {
  count = var.enable_function ? 1 : 0

  bucket = google_storage_bucket.function_source[0].name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.function_build[0].email}"
}

resource "google_artifact_registry_repository_iam_member" "function_build_image_writer" {
  count = var.enable_function ? 1 : 0

  location   = var.location
  repository = google_artifact_registry_repository.function_images[0].repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.function_build[0].email}"
}

resource "google_cloud_run_v2_service" "function" {
  count = var.enable_function ? 1 : 0

  name                = var.function_name
  location            = var.location
  ingress             = var.ingress
  deletion_protection = var.deletion_protection

  # Same annotations pathway as the plain services — this IS a Cloud Run
  # service, so the cloudRun provider discovers it identically.
  annotations = merge(var.common_annotations, var.function_annotations)
  labels      = merge(var.common_labels, var.function_labels)

  template {
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      # Placeholder until the first build completes; Cloud Run then serves the
      # built function image.
      image          = "us-docker.pkg.dev/cloudrun/container/hello"
      base_image_uri = "${var.location}-docker.pkg.dev/serverless-runtimes/google-22-full/runtimes/nodejs22"

      env {
        name  = "WHOAMI_NAME"
        value = var.function_name
      }
    }
  }

  build_config {
    source_location          = "gs://${google_storage_bucket.function_source[0].name}/${google_storage_bucket_object.function_source[0].name}"
    function_target          = "whoami"
    image_uri                = "${var.location}-docker.pkg.dev/${data.google_project.current.project_id}/${google_artifact_registry_repository.function_images[0].repository_id}/${var.function_name}"
    base_image               = "${var.location}-docker.pkg.dev/serverless-runtimes/google-22-full/runtimes/nodejs22"
    enable_automatic_updates = true
    service_account          = google_service_account.function_build[0].id
  }

  depends_on = [
    google_project_iam_member.function_build_act_as,
    google_project_iam_member.function_build_logs_writer,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "function_invoker" {
  count = var.enable_function && var.enable_unauthenticated ? 1 : 0

  name     = google_cloud_run_v2_service.function[0].name
  location = var.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
