# remove-vm.ps1 -- idempotent teardown of one module-created VM: turn off, remove,
# delete the differencing disk + seed ISO. Runs ON the Hyper-V host (terraform's
# destroy-time provisioner drives it over WinRM). Safe on an already-absent VM, so
# a re-run after a half-finished destroy converges instead of failing.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Name,
  [Parameter(Mandatory)][string]$VmDir,
  [string]$SeedDir = ""
)
$ErrorActionPreference = "Stop"
function Log([string]$m) { Write-Host "==> [$Name] $m" }

$vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
if ($vm) {
  if ($vm.State -ne "Off") {
    Log "turning off"
    Stop-VM -Name $Name -TurnOff -Force
  }
  Log "removing VM"
  Remove-VM -Name $Name -Force
} else {
  Log "VM already absent"
}

if (Test-Path $VmDir) {
  Log "deleting $VmDir (differencing disk + seed ISO)"
  Remove-Item $VmDir -Recurse -Force
}
if ($SeedDir -and (Test-Path $SeedDir)) {
  Log "deleting $SeedDir (seed files + these scripts)"
  # This deletes the RUNNING script's own file, which PowerShell tolerates: the
  # script is already read into memory.
  Remove-Item $SeedDir -Recurse -Force
}
Log "removed"
