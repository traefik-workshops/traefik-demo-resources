# Ephemeral by default — the last PVC in the fleet.
#
# Left at chart defaults this StatefulSet asks for one 8Gi RWO claim
# (`data-<release>-0`, mounted at /data), which on a managed cluster is a real, billed
# cloud disk with the same async-reclaim exposure that made Loki's claims outlive their
# demos: the CSI DeleteVolume call is made by a controller that `terraform destroy`
# removes moments after the PVC. Worse than Loki's here — this chart's
# `persistentVolumeClaimRetentionPolicy` defaults to `enabled: false` with
# `whenDeleted: Retain`, so the claim is not even deleted with the StatefulSet.
#
# Turning it off is FREE, which is not obvious and is the reason this note exists.
# The instinct is that an empty Redis after a restart means re-issuing certificates,
# and on a demo running Let's Encrypt PROD that would be a rate-limit incident rather
# than a saved disk. It cannot happen: Hub's ACME store is never Redis. Distributed
# ACME accepts Kubernetes secrets or Vault and nothing else (hub/pkg/hub/acme/
# distributed_builder.go switches on `Storage.Kubernetes` / `Storage.Vault`, and errors
# with "a storage must be defined" otherwise), the non-distributed path writes an
# acme.json FILE, and ../../../traefik/shared/helm_values.tf only ever renders
# `distributedAcme.storage.kubernetes = true`. The one thing `hub.redis` backs in this
# library is API Management's plan middleware — "RateLimit and Quota can be used only if
# the redis server is configured" (hub/pkg/middleware/plan/plan.go). So the state at
# risk is quota and rate-limit COUNTERS, which a restart resets to zero and the next
# request rebuilds.
#
# No volume plumbing is needed, unlike the Loki/MinIO fix: this chart already emits
# `data: emptyDir: {}` at the same /data mount when persistence is off.
#
# Set `persistence = true` to go back to a PVC — and then own the teardown.
resource "helm_release" "redis" {
  name       = var.name
  namespace  = var.namespace
  repository = "oci://registry-1.docker.io/"
  chart      = "cloudpirates/redis"
  version    = "0.4.6"
  timeout    = 900
  atomic     = true

  values = [
    yamlencode(merge({
      auth = {
        password = var.password
      }
      replica = {
        replicaCount = var.replica_count
      }
      persistence = {
        enabled = var.persistence
      }
    }, var.extra_values))
  ]
}
