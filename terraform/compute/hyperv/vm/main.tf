# =============================================================================
# compute/hyperv/vm — the shared Hyper-V VM primitive
# =============================================================================
# The Hyper-V sibling of compute/proxmox/vm, with one honest difference: there
# is no Terraform-native Hyper-V provider in this stack, and standalone Hyper-V
# has no REST API at all — management is PowerShell. So each VM is a HOST-SIDE
# POWERSHELL ONE-SHOT run over the host's WinRM HTTPS listener:
#
#   1. the caller-rendered NoCloud seed files (user-data, meta-data,
#      network-config) are uploaded to a per-VM seed directory,
#   2. scripts/new-vm.ps1 builds the seed ISO with the IMAPI2FS COM API
#      (volume label `cidata` — asserted after the build, because a wrong
#      label makes cloud-init silently ignore the whole seed),
#   3. a DIFFERENCING VHDX is created off the read-only golden parent
#      (var.parent_vhdx_path — the demo host bakes it; see the README), and
#   4. the VM is created (Gen 2, Secure Boot with the Microsoft UEFI CA
#      template so the Ubuntu shim boots), the seed attached, and started.
#
# ADDRESSING IS STATIC BY DESIGN. Hyper-V's only guest-IP readback is the KVP
# (Data Exchange) channel, which needs a daemon in the guest and is not
# readable at plan time — so unlike the proxmox/vsphere siblings this module
# never discovers an address: the caller PLANS one (each instance's
# network-config carries it, and ip_address echoes it back out). Plan-known
# addresses are what make the demo a single-pass apply with no PENDING uplink
# dance.
#
# ROLE CONFIG DOES NOT LIVE HERE. user_data / network_config arrive as opaque
# strings, and there is deliberately NO description/notes input: on the SCVMM
# topology the traefik.* label carrier is the VMM-side VM Description
# (Set-SCVirtualMachine on the VMM server — see apps/whoami/hyperv), and the
# host-side Hyper-V Notes field is never read by the discovery provider.
#
# POWERSHELL QUOTING TRAP (repo-wide rule for every script this module and its
# siblings ship): single-quoted PowerShell strings DO NOT collapse backtick
# escapes — 'HostSNI(``*``)' stores two literal backticks. Anything that can
# carry a backtick (Traefik label values, Host() rules) must ride
# double-quoted strings or — as these modules do — base64, never single-quoted
# literals.
# =============================================================================

locals {
  # Rendered NoCloud meta-data per instance: the instance key is the hostname.
  meta_data = {
    for key, inst in var.instances : key => "instance-id: ${key}\nlocal-hostname: ${key}\n"
  }

  seeds_root = "${var.workdir}\\seeds"
  vms_root   = "${var.workdir}\\vms"
}

resource "terraform_data" "vm" {
  for_each = var.instances

  # Any change here REPLACES the VM (destroy provisioner removes it, create
  # provisioner rebuilds): cloud-init runs on first boot only, and a
  # differencing disk is disposable by definition. The mirror of the proxmox
  # module's hash-named-snippet + replace_triggered_by mechanism.
  triggers_replace = [
    each.key,
    sha256(each.value.user_data),
    sha256(each.value.network_config),
    sha256(local.meta_data[each.key]),
    var.parent_vhdx_path,
    var.switch_name,
    coalesce(each.value.memory, var.memory),
    coalesce(each.value.num_cpus, var.num_cpus),
    var.generation,
  ]

  # Destroy-time provisioners may only reference `self`, so the connection
  # details ride in `input` (updated in place — a credential rotation does NOT
  # replace the VM).
  input = {
    host     = var.host_winrm.host
    port     = var.host_winrm.port
    username = var.host_winrm.username
    password = var.host_winrm.password
    https    = var.host_winrm.https
    insecure = var.host_winrm.insecure
    use_ntlm = var.host_winrm.use_ntlm
    timeout  = var.host_winrm.timeout
    name     = each.key
    seed_dir = "${local.seeds_root}\\${each.key}"
    vm_dir   = "${local.vms_root}\\${each.key}"
  }

  connection {
    type     = "winrm"
    host     = self.input.host
    port     = self.input.port
    user     = self.input.username
    password = self.input.password
    https    = self.input.https
    insecure = self.input.insecure
    use_ntlm = self.input.use_ntlm
    timeout  = self.input.timeout
  }

  # WinRM remote-exec runs through cmd.exe — `mkdir` ignores an existing dir
  # only with the `2>nul` guard, and every path stays backslashed.
  provisioner "remote-exec" {
    inline = [
      "if not exist \"${local.seeds_root}\\${each.key}\" mkdir \"${local.seeds_root}\\${each.key}\"",
    ]
  }

  provisioner "file" {
    content     = each.value.user_data
    destination = "${local.seeds_root}\\${each.key}\\user-data"
  }

  provisioner "file" {
    content     = local.meta_data[each.key]
    destination = "${local.seeds_root}\\${each.key}\\meta-data"
  }

  provisioner "file" {
    content     = each.value.network_config
    destination = "${local.seeds_root}\\${each.key}\\network-config"
  }

  # Both scripts land in the per-VM seed dir (not a shared path: parallel
  # instance creations must never race on one file). remove-vm.ps1 is uploaded
  # NOW because destroy-time can no longer upload anything.
  provisioner "file" {
    source      = "${path.module}/scripts/new-vm.ps1"
    destination = "${local.seeds_root}\\${each.key}\\new-vm.ps1"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/remove-vm.ps1"
    destination = "${local.seeds_root}\\${each.key}\\remove-vm.ps1"
  }

  provisioner "remote-exec" {
    inline = [
      join(" ", [
        "powershell -NoProfile -ExecutionPolicy Bypass",
        "-File \"${local.seeds_root}\\${each.key}\\new-vm.ps1\"",
        "-Name \"${each.key}\"",
        "-SeedDir \"${local.seeds_root}\\${each.key}\"",
        "-VmDir \"${local.vms_root}\\${each.key}\"",
        "-ParentVhdx \"${var.parent_vhdx_path}\"",
        "-SwitchName \"${var.switch_name}\"",
        "-MemoryMB ${coalesce(each.value.memory, var.memory)}",
        "-Cpus ${coalesce(each.value.num_cpus, var.num_cpus)}",
        "-Generation ${var.generation}",
      ]),
    ]
  }

  # Teardown removes the VM and its differencing disk. This needs the HOST
  # still reachable: destroy the guests while the box is up (the demos'
  # dependency order does), and use the documented -target=module.metal escape
  # hatch when a dead box strands the guest resources.
  provisioner "remote-exec" {
    when = destroy
    inline = [
      "powershell -NoProfile -ExecutionPolicy Bypass -File \"${self.input.seed_dir}\\remove-vm.ps1\" -Name \"${self.input.name}\" -VmDir \"${self.input.vm_dir}\" -SeedDir \"${self.input.seed_dir}\"",
    ]
  }
}
