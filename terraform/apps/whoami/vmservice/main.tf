# whoami on vSphere VM Service VMs — the SECOND way to provision a vSphere VM.
#
# Same hypervisor, same vCenter inventory, same Hub vsphere provider reading the label block
# from the VM Notes as apps/whoami/vsphere; what differs is WHO creates the machine. Not a terraform
# clone into a resource pool: a `VirtualMachine` object that the vSphere Supervisor's VM
# Service (vm-operator) reconciles inside a vSphere Namespace — built from a
# VirtualMachineImage in the namespace's content library, sized by a VirtualMachineClass,
# stored on the namespace's storage class, attached to the namespace's own NSX segment, and
# bootstrapped by the cloud-init user-data this module hands it in a Secret. Kubernetes-native
# provisioning of a plain vSphere VM: the VMware-shaped sibling of a KubeVirt guest, except
# the result IS a vCenter VM (VMware Tools, a guest address, a Notes field), so the
# vCenter-native provider finds it exactly like a clone.
#
# TWO THINGS THIS MODULE DOES THAT THE CLONE SIBLING DOES NOT:
#   * it WAITS for the guest address (status.network.primaryIP4). vm-operator assigns it
#     from the namespace network after power-on, so nothing about the VM is known at plan
#     time — a caller that needs the address at plan (a hub dialling a child) cannot get it
#     from here; see the README.
#   * it WRITES the label block into the VM Notes itself, through govc. vm-operator's
#     VirtualMachine has no field that reaches the vCenter config.annotation, and terraform's
#     vmware/vsphere provider can only set the Notes of a VM it created — this VM was created
#     by the Supervisor. The VM is located by its BIOS UUID, never by name: names are not
#     unique across vCenter folders.

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

  # The native vsphere provider reads LINE-FORMAT labels from the VM Notes (one
  # `traefik.<key>=<value>` per line; blank lines and `# comments` tolerated). Render the
  # dotted label map into that block — the apps/whoami/vsphere renderer, deliberately
  # duplicated rather than shared.
  descriptions = {
    for k, inst in local.instances_map :
    k => join("\n", [for lk, lv in inst.traefik_labels : "${lk}=${lv}"])
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

  yaml_body = yamlencode({
    apiVersion = local.api_version
    kind       = "VirtualMachine"
    metadata = {
      name      = each.key
      namespace = var.namespace
      labels    = local.labels[each.key]
    }
    spec = merge(
      {
        className    = var.class_name
        imageName    = var.image_name
        storageClass = var.storage_class
        powerState   = "PoweredOn"
        bootstrap = {
          cloudInit = {
            rawCloudConfig = { name = "${each.key}-bootstrap", key = "user-data" }
          }
        }
      },
      # Omitted = the namespace's default network. Named = one interface on that network
      # (an NSX segment or VDS port group the namespace is allowed to use).
      var.network_name != "" ? {
        network = { interfaces = [{ name = "eth0", network = { name = var.network_name } }] }
      } : {},
    )
  })
}

# Wait for the guest address, then read it back together with the identities govc needs.
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

# The label block in each VM's Notes — how the Hub vsphere provider discovers it. Written by
# govc (see the header), keyed off the VM's BIOS UUID so a name clash with a clone-sibling VM
# in another folder cannot annotate the wrong machine. Re-runs when the VM is replaced (new
# uuid) or the rendered block changes; `vm.change -annotation` REPLACES the Notes, so a re-run
# converges on the rendered block by construction.
resource "null_resource" "annotation" {
  for_each = { for key, inst in local.instances_map : key => inst if length(inst.traefik_labels) > 0 }

  triggers = {
    bios_uuid = data.external.guest[each.key].result.bios_uuid
    sha       = sha256(local.descriptions[each.key])
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/annotate.sh"
    environment = {
      GOVC_URL      = "https://${var.vsphere_server}"
      GOVC_USERNAME = var.vsphere_username
      GOVC_PASSWORD = var.vsphere_password
      GOVC_INSECURE = var.allow_unverified_ssl ? "1" : "0"
      VM_UUID       = self.triggers.bios_uuid
      # The block rides the environment, never a shell argument: multi-line and
      # backtick-safe.
      ANNOTATION = local.descriptions[each.key]
    }
  }
}
