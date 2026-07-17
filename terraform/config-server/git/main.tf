# =============================================================================
# git-config-server — the GitOps config repo, hosted in the hub cluster
# =============================================================================
# A single-replica smart-HTTP git server (terraform/config-server/git/image) serving a bare
# config.git with anonymous read+write, exposed at git.<domain> on the hub's websecure (:443)
# entrypoint — the SAME route the spokes already use for collector.<domain>, so it reaches
# every spoke (on-prem AND cloud) and the operator with zero new networking.
#
# The spokes git-pull <gateway>/dynamic.yaml from here into their file-provider watch dir and
# hot-reload; terraform pushes changes here instead of baking them into user_data. No token —
# a short-lived demo on a private lab net (see the repo README). The repo lives on an emptyDir:
# it is the SOURCE OF TRUTH only transiently — terraform re-pushes the full desired config on
# every apply, so a pod restart (empty repo re-seeded by the entrypoint) self-heals on the next
# apply. Persistence would only matter for out-of-band commits, which the demo does not make.
# =============================================================================

locals {
  labels = { app = var.name }
}

resource "kubernetes_deployment_v1" "git" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = 1 # one writer; the repo is an emptyDir, so >1 would diverge
    selector {
      match_labels = local.labels
    }
    template {
      metadata {
        labels = local.labels
      }
      spec {
        container {
          name              = "git"
          image             = var.image
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 80
          }
          volume_mount {
            name       = "repo"
            mount_path = "/srv/git"
          }
          readiness_probe {
            http_get {
              # info/refs is served only once the repo exists + the CGI works.
              path = "/config.git/info/refs?service=git-upload-pack"
              port = 80
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }
        }
        volume {
          name = "repo"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "git" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = local.labels
    port {
      port        = 80
      target_port = 80
    }
  }
}

# git.<domain> on websecure -> the git service. observability annotations off: the config
# pulls are lab plumbing, not demo request traffic, and would otherwise pollute the service
# graph / access logs.
resource "kubernetes_manifest" "ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = var.name
      namespace = var.namespace
      annotations = {
        "traefik.ingress.kubernetes.io/router.observability.accesslogs" = "false"
        "traefik.ingress.kubernetes.io/router.observability.metrics"    = "false"
        "traefik.ingress.kubernetes.io/router.observability.tracing"    = "false"
      }
    }
    spec = {
      entryPoints = [var.ingress_entrypoint]
      routes = [
        {
          kind  = "Rule"
          match = "Host(`${var.ingress_host}`)"
          services = [
            {
              name      = kubernetes_service_v1.git.metadata[0].name
              namespace = var.namespace
              port      = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_deployment_v1.git]
}
