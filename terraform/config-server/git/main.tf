# =============================================================================
# git-config-server — the GitOps config repo, hosted in the hub cluster
# =============================================================================
# A single-replica smart-HTTP git server (terraform/config-server/git/image) serving a bare
# config.git with anonymous read+write, exposed at git.<domain> on the hub's websecure (:443)
# entrypoint — the SAME route the spokes already use for collector.<domain>, so it reaches
# every spoke (on-prem AND cloud) and the operator with zero new networking.
#
# The READ path is raw HTTP: a post-receive hook checks the pushed tree out to a web root
# Apache serves at /config/<path>. That is what the spokes poll — a Hub provider's
# configEndpoint (gce/oci/ocici/vsphere: base services the provider injects discovered
# servers into) or Traefik's own http provider (a file-provider-shaped dynamic.yaml) —
# instead of baking config into user_data, which made every routing change a VM
# RECREATION. The WRITE path is terraform: var.files pushes the desired tree
# (null_resource.push below). No token — a short-lived demo on a private lab net (see the
# repo README). The repo lives on an emptyDir: it is the SOURCE OF TRUTH only transiently —
# terraform re-pushes the full desired config on every apply, so a pod restart (empty repo
# re-seeded by the entrypoint) self-heals on the next apply. Persistence would only matter
# for out-of-band commits, which the demo does not make.
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

# git.<domain> on websecure -> the git service. Delivered via a local-exec `kubectl apply`, NOT
# a kubernetes_manifest: kubernetes_manifest does a PLAN-TIME API call for the CRD schema, which
# fails on a FRESH apply where the k3s cluster is created in the same run ("Failed to construct
# REST client"). kubectl defers entirely to apply time, matching how the demo installs the
# Traefik CRDs. Uses the ambient kubeconfig context (k3s-<vm_name>) the k3s module merges.
# observability annotations off: config pulls are lab plumbing, not demo request traffic.
resource "null_resource" "ingressroute" {
  triggers = {
    host = var.ingress_host
    ns   = var.namespace
    ep   = var.ingress_entrypoint
    ctx  = var.kubeconfig_context
    svc  = kubernetes_service_v1.git.metadata[0].name
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      ctx=${var.kubeconfig_context != "" ? "--context ${var.kubeconfig_context}" : ""}
      kubectl $ctx apply -f - <<'YAML'
      apiVersion: traefik.io/v1alpha1
      kind: IngressRoute
      metadata:
        name: ${var.name}
        namespace: ${var.namespace}
        annotations:
          traefik.ingress.kubernetes.io/router.observability.accesslogs: "false"
          traefik.ingress.kubernetes.io/router.observability.metrics: "false"
          traefik.ingress.kubernetes.io/router.observability.tracing: "false"
      spec:
        entryPoints: ["${var.ingress_entrypoint}"]
        routes:
          - kind: Rule
            match: Host(`${var.ingress_host}`)
            services:
              - name: ${var.name}
                namespace: ${var.namespace}
                port: 80
      YAML
    EOT
  }

  depends_on = [kubernetes_deployment_v1.git, kubernetes_service_v1.git]
}

# The GitOps WRITE path: push var.files as the repo's tree, one commit per sync.
# The post-receive hook then publishes it raw under /config/, where the spokes'
# Hub providers poll their configEndpoint URLs — so changing routing intent is
# THIS resource re-running, never a gateway VM being replaced.
#
# Two deliberate choices:
#   - The push tunnels through `kubectl port-forward` to the Service instead of
#     the public git.<domain> URL: on a FRESH standup the DNS record
#     (dns-traefiker) and the ACME cert land minutes after the Deployment is
#     Ready, and the push is load-bearing (a provider polling an empty repo
#     serves no services). kubectl is already this module's delivery tool (the
#     IngressRoute above), and the port-forward needs nothing but the
#     kubeconfig context every demo merges during apply.
#   - It re-runs on EVERY apply (timestamp trigger), not on a content hash: the
#     repo lives on an emptyDir, so a pod restart re-seeds an EMPTY repo and a
#     hash-gated push would never notice — `terraform apply` must always
#     restore the full desired tree (the transient-source-of-truth contract in
#     the header). The push itself is idempotent: an unchanged tree makes no
#     commit.
resource "null_resource" "push" {
  count = length(var.files) > 0 ? 1 : 0

  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      ctx=${var.kubeconfig_context != "" ? "--context ${var.kubeconfig_context}" : ""}

      kubectl $ctx -n '${var.namespace}' rollout status 'deploy/${var.name}' --timeout=180s

      # Port-forward on a RANDOM local port (:80 -> the git Service) so parallel
      # demo standups on one machine can't collide; parse the port kubectl picked.
      pf_log=$(mktemp)
      work=$(mktemp -d)
      kubectl $ctx -n '${var.namespace}' port-forward 'svc/${var.name}' :80 >"$pf_log" 2>&1 &
      pf_pid=$!
      trap 'kill "$pf_pid" 2>/dev/null || true; rm -rf "$pf_log" "$work"' EXIT

      port=""
      for _ in $(seq 1 30); do
        port=$(sed -n 's/^Forwarding from 127.0.0.1:\([0-9][0-9]*\).*/\1/p' "$pf_log" | head -n 1)
        [ -n "$port" ] && break
        sleep 1
      done
      if [ -z "$port" ]; then
        echo "git-config-server port-forward never came up:" >&2
        cat "$pf_log" >&2
        exit 1
      fi

      git clone -q "http://127.0.0.1:$port/config.git" "$work/repo"
      cd "$work/repo"

      # The pushed tree IS the desired state: clear everything tracked, then
      # write the full file set (portable across BSD/GNU userlands).
      find . -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +
      %{~for path, content in var.files}
      mkdir -p "$(dirname '${path}')"
      printf '%s' '${base64encode(content)}' | openssl base64 -d -A > '${path}'
      %{~endfor}

      git add -A
      if git diff --cached --quiet; then
        echo "config repo already up to date"
      else
        git -c user.name=terraform -c user.email=terraform@demo commit -q -m "terraform: sync config tree"
        git push -q origin HEAD:main
      fi
    EOT
  }

  depends_on = [kubernetes_deployment_v1.git, kubernetes_service_v1.git]
}
