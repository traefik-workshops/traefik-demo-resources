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

  # Cloud Run pulls only from Artifact Registry, so the image is served through an
  # AR REMOTE (pull-through) repo whose upstream is WHATEVER registry the image
  # lives in — ghcr.io now that whoami ships there (a Docker-Hub-only mirror can't
  # serve a ghcr path). The first path segment is the registry host when it carries
  # a "." or ":"; otherwise the reference is a bare Docker Hub repo.
  image_segments = split("/", local.whoami_image_ref)
  has_host       = length(regexall("[.:]", local.image_segments[0])) > 0
  registry_host  = local.has_host ? local.image_segments[0] : "docker.io"
  upstream_uri   = local.registry_host == "docker.io" ? "https://registry-1.docker.io" : "https://${local.registry_host}"
  mirror_path    = local.has_host ? join("/", slice(local.image_segments, 1, length(local.image_segments))) : local.whoami_image_ref
  mirror_image   = "${var.location}-docker.pkg.dev/${data.google_project.current.project_id}/${var.mirror_repository_id}/${local.mirror_path}"
  image          = var.image != "" ? var.image : local.mirror_image
}

resource "google_artifact_registry_repository" "mirror" {
  count = var.enable_registry_mirror ? 1 : 0

  location      = var.location
  repository_id = var.mirror_repository_id
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"
  description   = "Pull-through mirror for ${local.registry_host} (Cloud Run can't pull external registries directly)"

  remote_repository_config {
    docker_repository {
      custom_repository {
        uri = local.upstream_uri
      }
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
# Optional "function" endpoint (enable_function)
# =============================================================================
# A second Cloud Run service the cloudRun provider discovers exactly like the
# plain ones (a gen2 Cloud Function IS a Cloud Run service). It runs the same
# whoami image rather than a source-built function image: terraform's
# build_config never persists (the Cloud Run API silently drops it, so no build
# is ever submitted and the service is stuck on the hello placeholder), making a
# from-source build unreliable here (gcp-unified-ingress validation, 2026-07).
# WHOAMI_NAME makes the body report `Name: <function_name>`.
# =============================================================================

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
      image = local.image

      # Cloud Run routes to container_port; WHOAMI_PORT_NUMBER makes whoami bind
      # it (whoami ignores Cloud Run's $PORT convention).
      ports {
        container_port = var.function_port
      }

      # Built-ins first so module/function `environment` wins on collision.
      dynamic "env" {
        for_each = merge(
          {
            WHOAMI_PORT_NUMBER = tostring(var.function_port)
            WHOAMI_NAME        = var.function_name
          },
          var.environment,
          var.function_environment,
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

resource "google_cloud_run_v2_service_iam_member" "function_invoker" {
  count = var.enable_function && var.enable_unauthenticated ? 1 : 0

  name     = google_cloud_run_v2_service.function[0].name
  location = var.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
