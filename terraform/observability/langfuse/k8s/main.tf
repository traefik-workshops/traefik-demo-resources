locals {
  web_service_name = "${var.name}-web"

  # Used by the app for callback / cookie domain. When ingress is on, point at
  # the externally-reachable URL; otherwise localhost port-forward style.
  nextauth_url = var.ingress ? "http://${var.ingress_host}:${var.ingress_external_port}" : "http://localhost:3000"

  otel_endpoint = "http://${local.web_service_name}.${var.namespace}.svc.cluster.local:3000/api/public/otel"

  init_env = [
    { name = "AUTH_DISABLE_SIGNUP", value = tostring(var.disable_signup) },
    { name = "LANGFUSE_INIT_ORG_ID", value = var.init_org_id },
    { name = "LANGFUSE_INIT_ORG_NAME", value = var.init_org_name },
    { name = "LANGFUSE_INIT_PROJECT_ID", value = var.init_project_id },
    { name = "LANGFUSE_INIT_PROJECT_NAME", value = var.init_project_name },
    { name = "LANGFUSE_INIT_PROJECT_PUBLIC_KEY", value = local.public_key },
    { name = "LANGFUSE_INIT_PROJECT_SECRET_KEY", value = local.secret_key },
    { name = "LANGFUSE_INIT_USER_EMAIL", value = var.init_user_email },
    { name = "LANGFUSE_INIT_USER_NAME", value = var.init_user_name },
    { name = "LANGFUSE_INIT_USER_PASSWORD", value = var.init_user_password },
  ]
}

# Auto-generate API keys so the Collector exporter can be wired without any
# manual UI round-trip. Consumers read them back via outputs.
resource "random_string" "public_key_suffix" {
  length  = 32
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "random_string" "secret_key_suffix" {
  length  = 32
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  public_key = "pk-lf-${random_string.public_key_suffix.result}"
  secret_key = "sk-lf-${random_string.secret_key_suffix.result}"
}

resource "helm_release" "langfuse" {
  name       = var.name
  namespace  = var.namespace
  repository = "https://langfuse.github.io/langfuse-k8s"
  chart      = "langfuse"
  version    = var.chart_version
  timeout    = 900
  wait       = false

  values = [
    yamlencode({
      langfuse = {
        deployment    = { replicas = var.replicas }
        salt          = { value = var.salt }
        encryptionKey = { value = var.encryption_key }
        nextauth = {
          url    = local.nextauth_url
          secret = { value = var.nextauth_secret }
        }
        additionalEnv = local.init_env
      }
      postgresql = {
        deploy = true
        auth   = { password = var.subchart_password, postgresPassword = var.subchart_password }
      }
      redis = {
        deploy = true
        auth   = { password = var.subchart_password }
      }
      clickhouse = {
        deploy = true
        auth   = { password = var.subchart_password }
      }
      s3 = {
        deploy = true
        auth   = { rootPassword = var.subchart_password }
        # 30Gi (default MinIO is 8Gi). Langfuse's OTLP trace ingestion writes one tiny S3
        # object per span — on the 8Gi/512K-inode default the drive hit 100% INODES (not bytes)
        # in ~5 days, and MinIO 500s ("minimum free drive threshold") -> traces silently dropped.
        # 30Gi ~= 1.9M inodes; pair with a retention/lifecycle policy for long-lived clusters.
        persistence = { size = "30Gi" }
      }
      # The bundled bitnami zookeeper (ClickHouse's coordinator) defaults to heapSize=1024
      # (1Gi JVM heap) but its resourcesPreset caps memory at 384Mi — the JVM is ~3x the cgroup
      # limit and OOMKills in a loop (265 restarts observed, destabilizing ClickHouse). Align
      # them: a 512Mi heap inside a 1Gi limit (heap + JVM/native overhead).
      zookeeper = {
        heapSize        = 512
        resourcesPreset = "none"
        resources = {
          requests = { cpu = "250m", memory = "512Mi" }
          limits   = { cpu = "500m", memory = "1Gi" }
        }
      }
    })
  ]
}

# IngressRoute is optional — turn on when you want to expose the UI via Traefik.
resource "kubernetes_manifest" "ingressroute" {
  count = var.ingress ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "${var.name}-web"
      namespace = var.namespace
      annotations = merge(
        var.ingress_observability ? {} : {
          "traefik.ingress.kubernetes.io/router.observability.accesslogs" = "false"
          "traefik.ingress.kubernetes.io/router.observability.metrics"    = "false"
          "traefik.ingress.kubernetes.io/router.observability.tracing"    = "false"
        },
        var.ingress_annotations,
      )
    }
    spec = {
      entryPoints = [var.ingress_entrypoint]
      routes = [
        {
          kind  = "Rule"
          match = "Host(`${var.ingress_host}`)"
          services = [
            {
              name      = local.web_service_name
              namespace = var.namespace
              port      = 3000
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.langfuse]
}
