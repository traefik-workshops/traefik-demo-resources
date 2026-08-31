# whoami on vSphere VM Service VMs — the SECOND way to provision a vSphere VM.
#
# Same hypervisor, same vCenter inventory as apps/whoami/vsphere; what differs is WHO
# creates the machine — and therefore where the label block rides. Not a terraform
# clone into a resource pool: a `VirtualMachine` object that the vSphere Supervisor's VM
# Service (vm-operator) reconciles inside a vSphere Namespace — built from a
# VirtualMachineImage in the namespace's content library, sized by a VirtualMachineClass,
# stored on the namespace's storage class, attached to the namespace's own NSX segment, and
# bootstrapped by the cloud-init user-data this module hands it in a Secret. Kubernetes-native
# provisioning of a plain vSphere VM: the VMware-shaped sibling of a KubeVirt guest — and,
# like that sibling, discovered on Kubernetes terms. The clone sibling's label block rides
# the vCenter Notes for the vsphere provider; here the SAME block rides ONE Kubernetes
# annotation on the VirtualMachine CR (label_annotation, default `traefik.io/config`) for
# the Hub vmoperator provider. Same contract, carried where each provisioning model
# natively keeps its metadata — and no vCenter credential or privilege is involved at all.
#
# ONE THING THIS MODULE DOES THAT THE CLONE SIBLING DOES NOT: it WAITS for the guest
# address (status.network.primaryIP4). vm-operator assigns it from the namespace network
# after power-on, so nothing about the VM is known at plan time — a caller that needs the
# address at plan (a hub dialling a child) cannot get it from here; see the README.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>`.
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

locals {
  # "<app>-<replica>" keys, the scheme every whoami sibling uses. The key is also the
  # VirtualMachine object name and, through vm-operator, the guest's hostname — so pick an
  # app key that is unique in the vCenter inventory (names are only unique per folder, and
  # `govc find -name` would otherwise see a clone-sibling's VM of the same name).
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key            = "${app_name}-${replica_idx + 1}"
        app_name       = app_name
        name           = try(app_config.name, app_name)
        traefik_labels = try(app_config.traefik_labels, {})
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }

  api_version = "vmoperator.vmware.com/${var.api_version}"
  # vSphere 8U2's WCP serves ONLY vmoperator.vmware.com/v1alpha1, whose VirtualMachine schema
  # predates spec.bootstrap: cloud-init rides spec.vmMetadata (a Secret + transport CloudInit)
  # and powerState is the lowercase enum. v1alpha2+ (VCF 9) uses spec.bootstrap.cloudInit.
  is_v1a1 = var.api_version == "v1alpha1"

  # spec.imageName is the VirtualMachineImage RESOURCE name and is IMMUTABLE. v1alpha2+ names the
  # image by var.image_name (resolves to itself); v1alpha1 names it vmi-<hash> and carries
  # var.image_name only in status.imageName. Resolve it up front so the VM is created correct.
  resolved_image = try(data.external.image.result.name, var.image_name)

  # The vmoperator provider reads LINE-FORMAT labels (one `traefik.<key>=<value>` per
  # line; blank lines and `# comments` tolerated) out of ONE annotation on the CR. Render
  # the dotted label map into that block — the apps/whoami/vsphere renderer, deliberately
  # duplicated rather than shared; the vsphere sibling puts the same block in the Notes.
  descriptions = {
    for k, inst in local.instances_map :
    k => join("\n", [for lk, lv in inst.traefik_labels : "${lk}=${lv}"])
  }

  # Discovery config travels in an ANNOTATION, never labels: a label value is capped at 63
  # characters from a restricted alphabet, and an annotation KEY's name segment carries the
  # same cap — which real Traefik keys like `...loadbalancer.sticky.cookie.name` exceed. The
  # single line-format annotation has no such ceilings. Set label_annotation = "" to emit
  # discrete `traefik.*` annotations instead (short keys only).
  vm_annotations = {
    for k, inst in local.instances_map : k => (
      length(inst.traefik_labels) == 0 ? {} :
      var.label_annotation != "" ? { (var.label_annotation) = local.descriptions[k] } : inst.traefik_labels
    )
  }

  labels = {
    for key, inst in local.instances_map :
    key => merge(var.common_labels, { "app.kubernetes.io/name" = inst.name })
  }

  # The kubectl the wait script runs: pinned to the caller's kubeconfig + context, never the
  # machine-global current-context (a parallel standup repoints that mid-apply).
  kubectl = join(" ", compact([
    "kubectl",
    var.kubeconfig != "" ? "--kubeconfig ${var.kubeconfig}" : "",
    var.kubeconfig_context != "" ? "--context ${var.kubeconfig_context}" : "",
  ]))
}

# Resolve var.image_name -> the VirtualMachineImage RESOURCE name (see local.resolved_image).
# host/setup-vm-service-image.sh publishes the image BEFORE terraform runs, but the Supervisor
# materialises the VirtualMachineImage CR asynchronously, so resolve-image.sh POLLS for it: a fresh
# plan can outrun the reconcile, and spec.imageName is immutable so a fallback-at-create is
# unrecoverable (see the script header). A miss after the poll budget falls back to var.image_name
# (the destroy-plan / torn-down-namespace case).
data "external" "image" {
  program = ["bash", "${path.module}/scripts/resolve-image.sh"]
  query = {
    kubectl    = local.kubectl
    namespace  = var.namespace
    image_name = var.image_name
  }
}

# The guest's cloud-init lives in a Secret: vm-operator's rawCloudConfig bootstrap reads the
# user-data out of a Secret key (plain, base64 or gzip+base64 — plain here). The key name is
# ours to choose; `user-data` is the conventional one.
resource "kubectl_manifest" "bootstrap" {
  for_each = local.instances_map

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "${each.key}-bootstrap"
      namespace = var.namespace
      labels    = local.labels[each.key]
    }
    stringData = { "user-data" = module.cloud_init[each.value.app_name].rendered }
  })
}

resource "kubectl_manifest" "vm" {
  for_each = local.instances_map

  # The Secret must exist before vm-operator reconciles the VM, or the bootstrap is
  # rejected and the guest powers on with no user-data.
  depends_on = [kubectl_manifest.bootstrap]

  # v1alpha1 (vSphere 8U2) and v1alpha2+ (VCF 9) have DIFFERENT VirtualMachine schemas, so the
  # whole body is version-split at yamlencode (two strings unify where two differently-shaped
  # objects would not). metadata is identical; only the spec differs: v1alpha1 rides cloud-init
  # on spec.vmMetadata (Secret + CloudInit transport) with the lowercase powerState and expresses
  # a named net as spec.networkInterfaces; v1alpha2+ uses spec.bootstrap.cloudInit.rawCloudConfig,
  # PoweredOn and spec.network.interfaces. The same "${each.key}-bootstrap" Secret feeds both.
  yaml_body = local.is_v1a1 ? yamlencode({
    apiVersion = local.api_version
    kind       = "VirtualMachine"
    metadata = {
      name        = each.key
      namespace   = var.namespace
      labels      = local.labels[each.key]
      annotations = local.vm_annotations[each.key]
    }
    spec = merge(
      {
        className    = var.class_name
        imageName    = local.resolved_image
        storageClass = var.storage_class
        powerState   = "poweredOn"
        vmMetadata   = { secretName = "${each.key}-bootstrap", transport = "CloudInit" }
      },
      var.network_name != "" ? {
        networkInterfaces = [{ networkName = var.network_name, networkType = "vsphere-distributed" }]
      } : {},
    )
    }) : yamlencode({
    apiVersion = local.api_version
    kind       = "VirtualMachine"
    metadata = {
      name        = each.key
      namespace   = var.namespace
      labels      = local.labels[each.key]
      annotations = local.vm_annotations[each.key]
    }
    spec = merge(
      {
        className    = var.class_name
        imageName    = local.resolved_image
        storageClass = var.storage_class
        powerState   = "PoweredOn"
        bootstrap    = { cloudInit = { rawCloudConfig = { name = "${each.key}-bootstrap", key = "user-data" } } }
      },
      var.network_name != "" ? {
        network = { interfaces = [{ name = "eth0", network = { name = var.network_name } }] }
      } : {},
    )
  })
}

# Wait for the guest address, then read it back together with the VM's vCenter identity.
# Ordered behind the VirtualMachine; on a destroy plan, or before the object exists, the
# script returns empty fields instead of failing — see scripts/vm-ip.sh.
data "external" "guest" {
  for_each   = local.instances_map
  depends_on = [kubectl_manifest.vm]

  program = ["bash", "${path.module}/scripts/vm-ip.sh"]
  query = {
    kubectl   = local.kubectl
    namespace = var.namespace
    name      = each.key
    timeout   = tostring(var.ip_wait_timeout)
  }
}
