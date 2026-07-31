# whoami on KubeVirt guests — the VMs behind SUSE Harvester, OpenShift Virtualization
# and upstream KubeVirt, which are all the same `kubevirt.io/v1` CRDs. Discovered by the
# native first-party Hub kubevirt provider (--hub.providers.kubevirt.*), which reads a
# VirtualMachine's own annotations and resolves the backend from its running instance.
#
# THE GUEST RUNS A NATIVE PROCESS, NOT A CONTAINER. cloud-init crane-extracts the whoami
# fork's binary (entrypoint /whoami) out of its OCI image and runs it raw under the
# guest's systemd — no podman, no dockerd, no container runtime of any kind inside the
# VM. That is the same trick apps/whoami/proxmox uses for its LXC leg (main.tf:170-186),
# and it is SIMPLER here: a KubeVirt guest has a cloud-init user-data path, so there is
# no `pct push` contortion (that module pins its own crane release; the two are
# independent). Two things follow, and both are the point of this module:
#   * the process lives in the guest's own UTS namespace, so `os.Hostname()` — the
#     `Hostname:` line in the response body — is spec.template.spec.hostname, not a
#     container id that happens to look like one;
#   * the leg is a genuinely different RUNTIME from a docker/OCI leg on the same
#     substrate, which is what lets a demo put the two side by side honestly.
# The fork honours OTEL_*, so this leg still earns its own service-graph node — which is
# exactly why the binary comes from the fork's image rather than an upstream release.
#
# REPLICAS AND SERVICE NAMES — THE INVERSE OF apps/whoami/proxmox. That module FORBIDS
# `replicas > 1` together with `traefik_labels`, because the proxmox provider's same-named
# services overwrite each other and the extra guests would never be routed to. The
# kubevirt provider MERGES them instead (ServersLoadBalancer.Merge dedupes by server URL
# and appends, then `mergeable` DeepEquals the rest of the struct), so ONE byte-identical
# label map on N guests folds into ONE service with N servers. Here `replicas > 1` with
# labels is legal AND the recommended shape — see the README.

locals {
  # "<app>-<replica>" keys, the scheme every whoami sibling uses, so a caller reading
  # `instances` sees the same shape as an ec2/gce/vsphere instances map. The key is also
  # the VirtualMachine name and the guest hostname, which is what act-1-style
  # "distinct Hostname per backend" assertions read.
  instances = flatten([
    for app_name, app in var.apps : [
      for i in range(app.replicas) : {
        key  = "${app_name}-${i + 1}"
        name = try(app.name, app_name)
        port = try(app.port, 80)

        # WHOAMI_NAME FIRST so the caller's `environment` can still override it. The
        # value is what the body echoes as `Name:`, which is the exact string a scenario
        # suite asserts on. Same construction as apps/whoami/docker/main.tf:37-41.
        environment = merge(
          try(app.name, "") != "" ? { WHOAMI_NAME = app.name } : {},
          var.environment,
          try(app.environment, {}),
        )

        traefik_labels = try(app.traefik_labels, {})
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }

  # Line-format carrier, byte-identical to apps/whoami/proxmox/main.tf:64-67: one
  # `traefik.<key>=<value>` per line in a SINGLE annotation. The provider parses it with
  # extractTraefikAnnotations, and the map is identical on every guest — which is the
  # precondition for the merge described in the header.
  descriptions = {
    for k, inst in local.instances_map :
    k => join("\n", [for lk, lv in inst.traefik_labels : "${lk}=${lv}"])
  }

  # Discovery config travels in ANNOTATIONS, never labels: a label value is capped at 63
  # characters from a restricted alphabet and cannot hold a rule like
  # "Host(`whoami-vm.example.com`)". Two carriers, and the default is not arbitrary —
  # a single line-format annotation is the only one with no length ceiling on the KEY
  # side either (an annotation key is itself capped at 63 chars, which several real
  # Traefik label keys exceed; see the README's table), and `field.cattle.io/description`
  # is what Harvester's UI writes when an operator types into a VM's Description box.
  vm_annotations = {
    for k, inst in local.instances_map : k => (
      length(inst.traefik_labels) == 0 ? {} :
      var.label_annotation != "" ? { (var.label_annotation) = local.descriptions[k] } : inst.traefik_labels
    )
  }

  # OUR OWN identity label. NEVER `vm.kubevirt.io/name`: that is KubeVirt's
  # DeprecatedVirtualMachineNameLabel and its value is SanitizeHostname(vmi), i.e. it
  # tracks the hostname set below rather than the VM name. virt-controller copies every
  # VMI label onto the launcher pod, so this is the label a Service should select on and
  # the one a `kubectl wait -l ...` gate should use.
  vm_labels = {
    for k, inst in local.instances_map :
    k => merge(var.common_labels, { "app.kubernetes.io/name" = inst.name })
  }

  user_data = {
    for k, inst in local.instances_map : k => templatefile("${path.module}/userdata.tftpl", {
      port          = inst.port
      whoami_image  = var.whoami_image
      crane_version = var.crane_version
      env_lines     = join("\n", [for ek, ev in inst.environment : "Environment=\"${ek}=${ev}\""])
      # Read back out of the MERGED environment rather than off app.name, so a caller
      # that overrides WHOAMI_NAME via `environment` is not silently outvoted by a
      # --name flag carrying the original value.
      name_flag = lookup(inst.environment, "WHOAMI_NAME", "") != "" ? " --name ${lookup(inst.environment, "WHOAMI_NAME", "")}" : ""
    })
  }
}

# The guest's cloud-init lives in a Secret, not inline on the VM.
#
# KubeVirt's validating webhook REJECTS an inline cloudInitNoCloud userData over 2048
# bytes -- "userdata exceeds 2048 byte limit. Should use UserDataSecretRef for larger
# data". The systemd unit plus the crane fetch renders ~3.4 KB, so the VM is refused at
# ADMISSION: there is no half-booted guest to inspect, and nothing reveals the limit until
# a real cluster turns the object down.
#
# The key MUST be `userdata` (lowercase) -- that is the name KubeVirt looks up inside the
# referenced Secret.
resource "kubectl_manifest" "cloudinit" {
  for_each = local.instances_map

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "${each.key}-cloudinit"
      namespace = var.namespace
      labels    = local.vm_labels[each.key]
    }
    stringData = { userdata = local.user_data[each.key] }
  })
}

resource "kubectl_manifest" "vm" {
  for_each = local.instances_map

  # The Secret must exist before the VMI starts, or cloud-init comes up empty and whoami
  # never installs -- a failure that looks like a boot problem rather than an ordering one.
  depends_on = [kubectl_manifest.cloudinit]

  yaml_body = yamlencode({
    apiVersion = "kubevirt.io/v1"
    kind       = "VirtualMachine"

    metadata = {
      name      = each.key
      namespace = var.namespace
      labels    = local.vm_labels[each.key]
      # TOP-LEVEL VM annotations, NOT spec.template.metadata.annotations. The provider
      # lists VirtualMachines and reads the annotations off the VM object, and KubeVirt
      # does NOT propagate a VM's top-level annotations onto its VMI. The practical
      # payoff: editing this block is picked up by the provider's refresh poll WITHOUT
      # restarting the guest.
      annotations = local.vm_annotations[each.key]
    }

    spec = {
      # runStrategy, never `running` — setting both is rejected by the API server.
      runStrategy = var.run_strategy

      template = {
        metadata = {
          labels = merge(local.vm_labels[each.key], {
            # KubeVirt's own VM-name label (kubevirt.io/vm), set to what KubeVirt would
            # set it to. Informational; the selector label above is the one to rely on.
            "kubevirt.io/vm" = each.key
          })
        }

        spec = {
          # hostname lives on VirtualMachineInstanceSpec, i.e. spec.template.spec — NOT
          # on VirtualMachineSpec. A `spec.hostname` is pruned server-side with no error,
          # which gives kubectl_manifest a permanent non-converging diff AND silently
          # voids the distinct-`Hostname:` property this module exists to provide.
          hostname = each.key

          # Real readiness. tcpSocket is dialled by the kubelet against the virt-launcher
          # pod and masquerade forwards it into the guest, so NO guest agent is involved.
          # This is what makes `kubectl wait --for=condition=Ready vmi` mean "whoami is
          # listening" instead of "the VMI booted" — first boot is minutes (containerDisk
          # pull, apt, crane download, crane export), and without this a caller races an
          # empty pool. failureThreshold x periodSeconds = 5 minutes past the delay.
          readinessProbe = {
            tcpSocket           = { port = each.value.port }
            initialDelaySeconds = 30
            periodSeconds       = 10
            failureThreshold    = 30
          }

          domain = {
            cpu    = { cores = var.cores }
            memory = { guest = var.memory }

            devices = {
              # BOTH a disks entry AND a volumes entry for the cloud-init drive.
              # Declaring only the volume produces a VM that boots with no user-data and
              # no error at all — whoami simply never appears.
              disks = [
                { name = "root", disk = { bus = "virtio" } },
                { name = "cloudinit", disk = { bus = "virtio" } },
              ]
              # masquerade with NO `ports` section: KubeVirt forwards ALL ports into the
              # guest when the section is absent, and SNATs egress through the launcher
              # pod — which is also why the guest inherits the pod's cluster DNS and can
              # resolve in-cluster Services (an OTLP collector, say) with no lab DNS.
              interfaces               = [{ name = "default", masquerade = {} }]
              autoattachGraphicsDevice = false
            }
          }

          networks = [{ name = "default", pod = {} }]

          volumes = [
            # containerDisk: a read-only OCI root with an ephemeral overlay. No PVC, no
            # StorageClass, no CDI DataVolume — the guests take no storage dependency.
            { name = "root", containerDisk = { image = var.container_disk } },
            { name = "cloudinit", cloudInitNoCloud = { secretRef = { name = "${each.key}-cloudinit" } } },
          ]
        }
      }
    }
  })
}
