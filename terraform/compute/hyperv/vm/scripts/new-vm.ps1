# new-vm.ps1 — idempotent one-shot: NoCloud seed ISO + differencing VHDX + Hyper-V VM.
#
# Runs ON the Hyper-V host (terraform drives it over WinRM). Convergence model is
# recreate-from-scratch: if the VM exists it is torn down first — terraform only calls
# this on create/replace, and a differencing disk is disposable by definition.
#
# QUOTING RULE (repo-wide): single-quoted PowerShell strings do NOT collapse backtick
# escapes — 'HostSNI(``*``)' stores TWO literal backticks. Nothing here interpolates
# label values (labels are VMM-side, base64-delivered — see apps/whoami/hyperv), but
# keep every string that could ever carry a backtick double-quoted all the same.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Name,
  [Parameter(Mandatory)][string]$SeedDir,
  [Parameter(Mandatory)][string]$VmDir,
  [Parameter(Mandatory)][string]$ParentVhdx,
  [Parameter(Mandatory)][string]$SwitchName,
  [int]$MemoryMB = 4096,
  [int]$Cpus = 2,
  [int]$Generation = 2
)
$ErrorActionPreference = "Stop"
function Log([string]$m) { Write-Host "==> [$Name] $m" }

# --- preconditions -----------------------------------------------------------------
if (-not (Test-Path $ParentVhdx)) { throw "parent VHDX not found: $ParentVhdx (host prep's golden phase builds it)" }
if ((Get-ItemProperty $ParentVhdx).IsReadOnly -ne $true) {
  # A writable parent is a corruption hazard: ANY write to it invalidates every child.
  Log "parent VHDX is writable — marking it read-only (differencing-parent hygiene)"
  Set-ItemProperty $ParentVhdx -Name IsReadOnly -Value $true
}
foreach ($f in "user-data", "meta-data", "network-config") {
  if (-not (Test-Path (Join-Path $SeedDir $f))) { throw "seed file missing: $SeedDir\$f" }
}
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
  throw "virtual switch '$SwitchName' does not exist (host prep's lab phase creates it)"
}

# --- tear down any prior incarnation ----------------------------------------------
$existing = Get-VM -Name $Name -ErrorAction SilentlyContinue
if ($existing) {
  Log "VM already exists — removing (recreate-from-scratch convergence)"
  if ($existing.State -ne "Off") { Stop-VM -Name $Name -TurnOff -Force }
  Remove-VM -Name $Name -Force
}
if (Test-Path $VmDir) { Remove-Item $VmDir -Recurse -Force }
New-Item -ItemType Directory -Path $VmDir -Force | Out-Null

# --- seed ISO via IMAPI2FS COM (no oscdimg/ADK dependency on a bare host) ----------
# The seed dir must contain ONLY the three NoCloud files at its root; scripts uploaded
# alongside them are excluded via a staging copy.
$stage = Join-Path $VmDir "seed-stage"
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($f in "user-data", "meta-data", "network-config") {
  Copy-Item (Join-Path $SeedDir $f) (Join-Path $stage $f)
}
$isoPath = Join-Path $VmDir "seed.iso"
Log "building NoCloud seed ISO ($isoPath)"

if (-not ([System.Management.Automation.PSTypeName]"TraefikLab.IsoWriter").Type) {
  Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
namespace TraefikLab {
  public static class IsoWriter {
    public static void Write(string path, object streamObj, int blockSize, int totalBlocks) {
      IStream stream = (IStream)streamObj;
      using (FileStream fs = File.Create(path)) {
        byte[] buf = new byte[blockSize];
        IntPtr pcb = Marshal.AllocHGlobal(sizeof(int));
        try {
          for (int i = 0; i < totalBlocks; i++) {
            stream.Read(buf, blockSize, pcb);
            int read = Marshal.ReadInt32(pcb);
            if (read <= 0) { break; }
            fs.Write(buf, 0, read);
          }
        } finally { Marshal.FreeHGlobal(pcb); }
      }
    }
  }
}
"@
}

$fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$fsi.FileSystemsToCreate = 3          # ISO9660 + Joliet
$fsi.VolumeName = "cidata"            # NoCloud REQUIRES this exact label
$fsi.Root.AddTree($stage, $false)
$img = $fsi.CreateResultImage()
[TraefikLab.IsoWriter]::Write($isoPath, $img.ImageStream, $img.BlockSize, $img.TotalBlocks)
Remove-Item $stage -Recurse -Force

# ASSERT the label. cloud-init matches the NoCloud drive by FileSystemLabel: a wrong
# label produces a VM that boots clean and silently ignores the whole seed — the
# worst failure shape, so it is checked here rather than discovered in the guest.
Mount-DiskImage -ImagePath $isoPath | Out-Null
try {
  $label = (Get-DiskImage -ImagePath $isoPath | Get-Volume).FileSystemLabel
  if ($label -cne "cidata") { throw "seed ISO label is '$label', want 'cidata' — cloud-init would ignore this seed" }
} finally {
  Dismount-DiskImage -ImagePath $isoPath | Out-Null
}
Log "seed ISO label asserted: cidata"

# --- differencing disk + VM --------------------------------------------------------
$diskPath = Join-Path $VmDir "$Name.vhdx"
Log "creating differencing VHDX off $ParentVhdx"
New-VHD -Path $diskPath -ParentPath $ParentVhdx -Differencing | Out-Null

Log "creating Gen$Generation VM (${MemoryMB}MB, $Cpus vCPU) on switch '$SwitchName'"
$vm = New-VM -Name $Name -Generation $Generation -MemoryStartupBytes ([int64]$MemoryMB * 1MB) `
  -VHDPath $diskPath -SwitchName $SwitchName -Path $VmDir
Set-VM -VM $vm -StaticMemory -AutomaticCheckpointsEnabled $false -CheckpointType Disabled
Set-VMProcessor -VM $vm -Count $Cpus
if ($Generation -eq 2) {
  # The Microsoft UEFI CA template is what signs the Ubuntu shim; the default
  # (Windows-only) template refuses to boot the cloud image.
  Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
}
$dvd = Add-VMDvdDrive -VM $vm -Path $isoPath -Passthru
if ($Generation -eq 2) {
  $hd = Get-VMHardDiskDrive -VM $vm
  Set-VMFirmware -VM $vm -BootOrder $hd, $dvd
}
# KVP (Data Exchange) + Guest Services on: KVP is how a human — and SCVMM's adapter
# view — reads the guest address; the golden image bakes the daemon.
Get-VMIntegrationService -VM $vm | Where-Object { -not $_.Enabled } |
  ForEach-Object { Enable-VMIntegrationService -VMIntegrationService $_ }

Start-VM -VM $vm
Log "VM started"
