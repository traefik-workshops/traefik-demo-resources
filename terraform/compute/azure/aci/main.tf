# =============================================================================
# compute/azure/aci — the shared azurerm_container_group both the Traefik child
# (traefik/aci) and the whoami backend (apps/whoami/aci) compose.
# =============================================================================
# One container group per entry in var.container_groups (the traefik caller
# passes a single entry; whoami passes one per app replica). Every attribute is
# moved verbatim from the two callers' former inline resources — role-specific
# content (commands, tags, env, secret volumes, identity) arrives as inputs.
# =============================================================================

locals {
  # --- the OTLP collector gate, container-native --------------------------------
  # EVERY VM leg in this library already waits for the collector before it starts
  # emitting: traefik/{ec2,gce,azure-vm,oci-vm,proxmox-vm,vsphere-vm,hyperv-vm,
  # morpheus-vm,alibaba-ecs} and apps/whoami/cloud-init all render
  # cloud-init-snippets/otlp-collector-gate.sh.tpl into first boot. The CONTAINER
  # legs (aci, ecs) never could: their images are scratch, there is no cloud-init,
  # and so they were the only legs that started exporting into the void.
  #
  # That asymmetry is exactly what the service map has been showing, run after run:
  #
  #   whoami-vm         gated    -> reports
  #   traefik-vm        gated    -> reports
  #   traefik-container UNGATED  -> reports
  #   whoami-container  UNGATED  -> reports ~30-45 MINUTES LATE, or not at all
  #
  # The last line is the important one, and it is a RACE, not a permanent failure --
  # a correction to what an earlier revision of this comment claimed. Measured on
  # azure-unified-ingress 2026-08-11: the group booted at 13:13:40 and its first
  # export failed immediately; it was still failing every single export at 13:34:25;
  # by roughly 14:00 it had recovered on its own and the service map came back
  # complete. The run BEFORE it, capturing the map ~35 minutes after the same boot,
  # came back MISSING whoami-container and failed.
  #
  # So the demo has been a coin flip decided by how long the harness happened to take
  # to reach the assertion, which is worse than a clean failure: it is a demo that
  # reports nothing for the first half hour somebody might be presenting it, and an
  # assertion that passes or fails on timing rather than on wiring. The gate turns
  # that coin flip into a certainty -- telemetry from the first request.
  #
  # Ordering terraform-side does NOT fix this and cannot. observability/dns-gate
  # blocks on the NAME resolving, and a name resolves perfectly well when it still
  # points at the PREVIOUS run's load balancer — observed on azure-unified-ingress
  # 2026-08-11, where the gate returned "resolves -- spokes may boot" in under a
  # second against an IP whose resource group had already been destroyed. Worse, the
  # gate sits UPSTREAM of the hub Traefik in these demos (the hub consumes the ACI
  # child's uplink address), so on a genuinely cold domain it would be waiting for a
  # record that its own dependents have to be created before anything can publish.
  #
  # An init container asks the only question that actually settles it — does this
  # endpoint accept an OTLP write RIGHT NOW — from inside the group's own network,
  # and the main container does not start until it does. Same probe, same 30-minute
  # bound, same "start anyway" ending as the VM snippet; the delivery is the only
  # thing that differs.
  otlp_gate_enabled = var.otlp_gate_address != ""

  # NOT the shared cloud-init snippet, and the difference is one flag that matters.
  #
  # That snippet probes with `curl -skf`. The -k skips certificate verification, so it
  # goes green the moment Traefik answers 2xx -- INCLUDING while Traefik is still serving
  # its own default self-signed certificate, before Let's Encrypt has issued. The
  # workload's OTel SDK does verify, so the gate opens and the exporter immediately fails
  # anyway. Measured on azure-unified-ingress 2026-08-11, gated run: the gate printed
  # "OTLP collector ready." on its FIRST attempt at 14:26, and the whoami it had just
  # released logged 62 consecutive
  #
  #   tls: failed to verify certificate: x509: certificate is valid for
  #   <random>.<random>.traefik.default, not collector.<domain>
  #
  # over the next five minutes. A gate that opens on a door the workload cannot walk
  # through is not a gate.
  #
  # So probe exactly as the workload does: verify the chain. The base image ships no CA
  # bundle (curl exits 60, ssl_verify_result=20 -- measured), so install one first and
  # degrade LOUDLY to insecure if that fails, because an unverified probe is still worth
  # more than no probe.
  otlp_gate_script = <<-EOT
    set -u
    addr="${var.otlp_gate_address}"

    # The workload verifies TLS; this probe has to, or it opens too early.
    verify="--fail"
    if ! tdnf install -y -q ca-certificates >/dev/null 2>&1; then
      echo "otlp-gate: WARNING could not install ca-certificates -- probing WITHOUT" >&2
      echo "otlp-gate: certificate verification, so this gate can open during the ACME" >&2
      echo "otlp-gate: window and the workload may still fail x509 for a few minutes." >&2
      verify="--fail --insecure"
    fi

    for i in $(seq 1 180); do
      if curl -s -o /dev/null $verify --max-time 5 \
           -X POST -H 'Content-Type: application/json' \
           -d '{"resourceMetrics":[]}' "$addr/v1/metrics"; then
        echo "otlp-gate: $addr accepted a verified OTLP write -- starting the workload"
        exit 0
      fi
      echo "otlp-gate: waiting for $addr to accept OTLP ($i/180)..."
      sleep 10
    done

    # Bounded on purpose: a collector that never arrives must degrade this group to
    # "runs, reports late", never to a container group that cannot start.
    echo "otlp-gate: $addr never accepted a write in 30m -- starting anyway." >&2
    exit 0
  EOT
}

resource "azurerm_container_group" "this" {
  for_each = var.container_groups

  name                = each.key
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = var.os_type
  restart_policy      = var.restart_policy

  # Private vnet-injected IP — the parent/child dials it in-vnet (ipMode=private).
  # The subnet MUST be delegated to Microsoft.ContainerInstance.
  ip_address_type = var.ip_address_type
  subnet_ids      = [var.subnet_id]

  # DefaultAzureCredential inside the container resolves this identity via the
  # ACI-injected identity endpoint (the Traefik child's aci-provider credential).
  dynamic "identity" {
    for_each = var.enable_system_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  dynamic "exposed_port" {
    for_each = toset(var.exposed_ports)
    content {
      port     = exposed_port.value
      protocol = "TCP"
    }
  }

  # ACI runs init containers to completion, in order, BEFORE the main container —
  # which is the whole point: the exporter cannot make its first doomed export until
  # the collector has answered one. The gate image only has to carry a shell and
  # curl; the workload images here are scratch, which is why the probe cannot live
  # in the container it protects.
  dynamic "init_container" {
    for_each = local.otlp_gate_enabled ? [1] : []
    content {
      name  = "otlp-collector-gate"
      image = var.otlp_gate_image
      # The gate always exits 0 — it is bounded and then gives up deliberately. A
      # non-zero exit here would leave the group restarting instead of degrading to
      # "runs, reports late", which is the wrong failure for a demo.
      commands = ["/bin/sh", "-c", local.otlp_gate_script]
    }
  }

  container {
    name     = var.container_name
    image    = var.image
    cpu      = var.container_cpu
    memory   = var.container_memory
    commands = var.commands

    dynamic "ports" {
      for_each = toset(each.value.ports)
      content {
        port     = ports.value
        protocol = "TCP"
      }
    }

    environment_variables = each.value.environment_variables

    # The Hub image is scratch (no shell/cloud-init) — a secret volume carries
    # the file-provider config, no init sidecar needed (unlike ECS).
    dynamic "volume" {
      for_each = var.volumes
      content {
        name       = volume.value.name
        mount_path = volume.value.mount_path
        secret     = volume.value.secret
      }
    }
  }

  tags = merge(var.common_tags, each.value.tags)
}
