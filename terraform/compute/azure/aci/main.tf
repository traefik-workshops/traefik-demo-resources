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
  #   traefik-container UNGATED  -> reports anyway (Hub's own exporter retries)
  #   whoami-container  UNGATED  -> MISSING
  #
  # The whoami fork's OTel SDK is the one exporter with no recovery path: pointed at
  # a dead endpoint at startup it stays dark indefinitely, which the cloud-init
  # snippet's own header records ("exporters that start against a dead endpoint were
  # observed to stay dark long after it healed", aws-unified-ingress 2026-07).
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

  otlp_gate_script = local.otlp_gate_enabled ? templatefile(
    "${path.module}/../../../cloud-init-snippets/otlp-collector-gate.sh.tpl",
    { otlp_address = var.otlp_gate_address }
  ) : ""
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
