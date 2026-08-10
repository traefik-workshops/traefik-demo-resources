# whoami on Hyper-V VMs under SCVMM — the on-prem sibling of apps/whoami/proxmox /
# apps/whoami/vsphere, discovered by the native first-party Hub Hyper-V provider
# (--hub.providers.hyperv.*, SCVMM-based; see traefik/hyperv-vm).
#
# THE LABEL CARRIER IS THE SCVMM VM **DESCRIPTION**, THE GRAMMAR IS PROXMOX'S:
# line-format `traefik.<key>=<value>`, one per line (`traefik.enable=true` is
# mandatory; blank lines and `# comments` are tolerated). The provider reads it
# from the VMM server with Get-SCVirtualMachine — the host-side Hyper-V Notes
# field is NEVER read.
#
# TWO PLANES, TWO CONNECTIONS — the module split the SCVMM design demands:
#   * VM CREATION is host-side (compute/hyperv/vm: WinRM to the Hyper-V HOST —
#     differencing VHDX + NoCloud seed one-shots).
#   * LABEL WRITING is VMM-side (terraform_data.labels below: WinRM to the
#     SCVMM SERVER running `Set-SCVirtualMachine -Description`). A label change
#     re-runs ONLY the writer — never a VM replacement — because the labels are
#     deliberately absent from the VM resources' triggers.
#
# THE PROVIDER MERGES SAME-NAMED SERVICES ACROSS VMs (identical labels on N
# guests fold into one N-server load balancer, like the vsphere/EC2 providers
# and UNLIKE proxmox's one-service-per-guest). So the whole fleet carries ONE
# shared label block: wrr rides the plain merged service, and leasttime/hrw are
# `loadbalancer.strategy` labels on their own merged services — no
# terraform-wired server lists, no weighted file compositions.
#
# LABEL DELIVERY IS BASE64, and that is a correctness decision, not a
# convenience: label values carry backticks (Host(`...`) rules), and PowerShell
# quoting has a documented trap here — single-quoted strings do NOT collapse
# backtick escapes ('HostSNI(``*``)' stores TWO literal backticks), so any
# naive quoting of a label line corrupts it. Use double-quoted strings when a
# human must interpolate; this module sidesteps interpolation entirely by
# shipping the description as base64 and decoding it on the VMM server.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-vm).
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

locals {
  # Replicate the siblings' instance-key scheme: "<app>-<replica>". Each
  # replica takes the app's ip_addresses[replica-1] — static, plan-known.
  instances = flatten([
    for app_name, app in var.apps : [
      for idx in range(app.replicas) : {
        key            = "${app_name}-${idx + 1}"
        app_name       = app_name
        ip_cidr        = app.ip_addresses[idx]
        ip             = split("/", app.ip_addresses[idx])[0]
        traefik_labels = try(app.traefik_labels, {})
      }
    ]
  ])
  instances_map = { for inst in local.instances : inst.key => inst }

  # Line-format label block per instance (the SCVMM Description content).
  # Identical across an app's replicas ON PURPOSE — that is what merges them
  # into one multi-server service (see the header).
  descriptions = {
    for k, inst in local.instances_map :
    k => join("\n", [for lk, lv in inst.traefik_labels : "${lk}=${lv}"])
  }

  network_configs = {
    for k, inst in local.instances_map : k => yamlencode({
      version = 2
      ethernets = {
        eth0 = merge(
          {
            addresses = [inst.ip_cidr]
            routes    = [{ to = "default", via = var.gateway }]
          },
          length(var.dns_servers) > 0 ? { nameservers = { addresses = var.dns_servers } } : {},
        )
      }
    })
  }
}

# --- The VMs (host-side) — the shared compute/hyperv/vm primitive -------------
module "vm" {
  source = "../../../compute/hyperv/vm"

  host_winrm       = var.host_winrm
  switch_name      = var.switch_name
  parent_vhdx_path = var.parent_vhdx_path
  workdir          = var.workdir
  num_cpus         = var.num_cpus
  memory           = var.memory

  instances = {
    for k, inst in local.instances_map : k => {
      user_data      = module.cloud_init[inst.app_name].rendered
      network_config = local.network_configs[k]
      ip_address     = inst.ip
    }
  }
}

# --- The labels (VMM-side) ----------------------------------------------------
# One writer per labeled VM, connecting to the SCVMM SERVER (var.vmm — an
# account with VMM WRITE rights: Set-SCVirtualMachine is not something the
# gateway's read-only discovery account can do). scripts/set-labels.ps1
# refreshes the owning host when VMM has not yet inventoried a just-created VM
# (VMM notices host changes on its refresher cadence, not instantly), then
# writes the Description.
resource "terraform_data" "labels" {
  for_each = { for k, inst in local.instances_map : k => inst if length(inst.traefik_labels) > 0 }

  # A label edit re-runs THIS resource only; recreating the VM re-runs it too
  # (the id changes), which re-labels the fresh VMM object.
  triggers_replace = [
    local.descriptions[each.key],
    module.vm.instances[each.key].id,
  ]

  input = {
    host     = var.vmm.host
    port     = var.vmm.port
    username = var.vmm.username
    password = var.vmm.password
    timeout  = var.vmm.timeout
    name     = each.key
  }

  connection {
    type     = "winrm"
    host     = self.input.host
    port     = self.input.port
    user     = self.input.username
    password = self.input.password
    https    = true
    insecure = true
    use_ntlm = true
    timeout  = self.input.timeout
  }

  provisioner "remote-exec" {
    inline = [
      "if not exist \"C:\\traefik-lab\" mkdir \"C:\\traefik-lab\"",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/set-labels.ps1"
    destination = "C:\\traefik-lab\\set-labels-${each.key}.ps1"
  }

  provisioner "remote-exec" {
    inline = [
      "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\traefik-lab\\set-labels-${each.key}.ps1\" -VMName \"${each.key}\" -DescriptionB64 \"${base64encode(local.descriptions[each.key])}\"",
    ]
  }
}
