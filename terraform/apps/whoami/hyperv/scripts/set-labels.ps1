# set-labels.ps1 -- write a VM's traefik.* label block into its SCVMM Description.
#
# Runs ON the SCVMM management server (terraform's label-writer drives it over WinRM
# with a VMM-write-capable account). Idempotent: Set-SCVirtualMachine converges the
# Description to exactly the decoded payload; re-running with the same payload is a
# no-op in effect.
#
# WHY BASE64: label values carry backticks (Host(`...`)) and Traefik rule syntax, and
# PowerShell quoting is a documented trap here -- SINGLE-QUOTED strings do NOT collapse
# backtick escapes ('HostSNI(``*``)' stores TWO literal backticks), so building the
# Description via string interpolation corrupts exactly the labels that matter. Use
# double-quoted strings when interpolation is unavoidable elsewhere; this script avoids
# interpolation entirely: the caller base64-encodes the finished line block and it is
# decoded byte-exact here (newlines included -- the provider tolerates LF and CRLF).
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$VMName,
  [Parameter(Mandatory)][string]$DescriptionB64
)
$ErrorActionPreference = "Stop"
function Log([string]$m) { Write-Host "==> [$VMName] $m" }

Import-Module VirtualMachineManager -ErrorAction Stop
$desc = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($DescriptionB64))

# A just-created host-side VM is invisible to VMM until its refresher next walks the
# host, so poll -- and force a host refresh mid-wait rather than trusting the cadence.
$vm = $null
for ($i = 1; $i -le 30; $i++) {
  $vm = Get-SCVirtualMachine -VMMServer localhost -Name $VMName
  if ($vm) { break }
  if ($i -eq 2 -or $i % 10 -eq 0) {
    Log "not in VMM inventory yet -- refreshing hosts (attempt $i/30)"
    Get-SCVMHost -VMMServer localhost | ForEach-Object { Read-SCVMHost -VMHost $_ -ErrorAction SilentlyContinue } | Out-Null
  }
  Start-Sleep -Seconds 10
}
if (-not $vm) { throw "VM '$VMName' never appeared in the VMM inventory (is the host's VMM agent healthy?)" }
if ($vm -is [array]) { throw "VM name '$VMName' is ambiguous in VMM ($($vm.Count) matches) -- labels refuse to guess" }

Log "writing Description ($([regex]::Matches($desc, "`n").Count + 1) label lines)"
Set-SCVirtualMachine -VM $vm -Description $desc | Out-Null

# Read-back assert: the write must round-trip byte-exact (the provider parses this
# exact field). A silent mangle here would surface as a VM quietly missing from
# discovery -- fail loudly instead.
$check = (Get-SCVirtualMachine -VMMServer localhost -Name $VMName).Description
if ($check -cne $desc) { throw "Description read-back mismatch on '$VMName' -- VMM did not store the label block byte-exact" }
Log "labels written and verified"
