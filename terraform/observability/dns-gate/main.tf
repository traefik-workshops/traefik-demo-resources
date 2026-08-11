# Block until a hostname actually RESOLVES in public DNS, then let dependents proceed.
#
# WHY THIS EXISTS -- a 30-minute failure that looks exactly like broken telemetry.
#
# Every spoke in these demos ships OTLP to `collector.<domain>`, a name published by the
# in-cluster dns-traefiker only AFTER the hub's Traefik LoadBalancer Service gets an
# address. Nothing ordered the spokes behind that, so they routinely booted first, and
# their very first lookup returned NXDOMAIN.
#
# An NXDOMAIN is not a transient miss: the resolver CACHES it, for the zone's SOA MINIMUM.
# For traefik.ai that is 1800 seconds. Diagnosed live on aws-unified-ingress 2026-08-11:
#
#   11:16:48  ECS tasks start, first OTLP export ->
#             lookup collector.aws.demo.traefik.ai on 10.0.0.2:53: no such host
#   11:26:04  hub Traefik LoadBalancer Service created -- the name could not have
#             existed one second earlier
#   11:28:36  dns-traefiker publishes the record
#   11:52:26  traefik-vm's first metrics land   <- ~30 min after the NXDOMAIN, not
#   11:57:26  traefik-container's first metrics    after the record appeared
#
# For half an hour the demo serves every request correctly and reports NOTHING. Routing
# assertions pass; the service map is empty or partial. It reads as a broken exporter,
# a bad endpoint, or a firewall -- and it is none of those. GCP shows the identical
# pattern and simply won the race often enough to look healthy.
#
# The fix is ordering, not retries: if the record exists BEFORE a spoke boots, that spoke
# never makes the lookup that gets negatively cached. Nothing downstream needs to know.
#
# Resolution is checked from the OPERATOR's machine, which is the right question to ask.
# The failure is caused by a lookup happening too EARLY, so what has to be established is
# that the name is publicly resolvable before any spoke exists. A spoke created after that
# cannot poison its own resolver.

terraform {
  required_version = ">= 1.5"

  # null is declared, not inherited: tflint's terraform_required_providers rule fails a
  # module that uses a provider without constraining it, and an unconstrained provider is
  # a real hazard here rather than a formality -- this module's entire behaviour is one
  # null_resource's local-exec, so a major-version drift underneath it changes what the
  # gate does with no signal at all.
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

resource "null_resource" "gate" {
  triggers = {
    hostname = var.hostname
    # Re-gate whenever the thing that publishes the record is replaced, so a rebuilt hub
    # does not let stale spokes race a newly-published name.
    upstream = var.upstream_id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -uo pipefail
      host="${var.hostname}"
      deadline=$(( SECONDS + ${var.timeout_seconds} ))
      echo "dns-gate: waiting for $host to resolve publicly (timeout ${var.timeout_seconds}s)"

      # Ask a PUBLIC resolver explicitly. The operator's own resolver may itself hold a
      # negative cache entry from an earlier run of this very demo, which would make the
      # gate wait out a TTL for no reason -- the exact trap it exists to prevent.
      resolves() {
        if command -v dig >/dev/null 2>&1; then
          [ -n "$(dig +short +time=3 +tries=1 @1.1.1.1 "$1" A 2>/dev/null | head -1)" ]
        else
          # No dig (minimal images): fall back to the system resolver.
          getent hosts "$1" >/dev/null 2>&1 || host "$1" >/dev/null 2>&1
        fi
      }

      while [ "$SECONDS" -lt "$deadline" ]; do
        if resolves "$host"; then
          echo "dns-gate: $host resolves -- spokes may boot"
          exit 0
        fi
        sleep 10
      done

      echo "dns-gate: $host did NOT resolve within ${var.timeout_seconds}s." >&2
      echo "dns-gate: letting spokes boot now would hand each of them an NXDOMAIN that" >&2
      echo "dns-gate: their resolver pins for the zone's SOA MINIMUM (1800s on traefik.ai)," >&2
      echo "dns-gate: so the demo would serve traffic correctly and report no telemetry" >&2
      echo "dns-gate: for the next half hour. Check that dns-traefiker is running and that" >&2
      echo "dns-gate: the hub's LoadBalancer Service actually got an address." >&2
      exit 1
    EOT
  }
}
