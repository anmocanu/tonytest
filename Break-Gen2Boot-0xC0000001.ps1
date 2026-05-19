<#
.SYNOPSIS
  Stages and triggers a one-time boot break on next startup.

.DESCRIPTION
  - Exits quickly when used from ARM Custom Script Extension (CSE-friendly).
  - Backs up BCD before change.
  - On next boot, sets winload path to a non-existent file to force boot failure.
  - Creates a restore script on disk.

.NOTES
  This intentionally makes the VM unbootable until restored.
#>

param(
    [switch]$DirectNow,     # If set, break immediately in current session (not CSE-friendly).
    [switch]$NoReboot       # If set, do not trigger reboot at the end.
)

$ErrorActionPreference = 'Stop'

$root = 'C:\ChaosBoot'
$breakerPath = Join-Path $root 'Apply-BootBreak.ps1'
$restorePath = Join-Path $root 'Restore-Boot.ps1'
$logPath = Join-Path $root 'stage.log'
$taskName = '\Chaos\BreakBootOnce'

New-Item -ItemType Directory -Path $root -Force | Out-Null

function Log([string]$msg) {
    $line = "$(Get-Date -Format s) $msg"
    $line | Out-File -FilePath $logPath -Append -Encoding ascii
    Write-Host $line
}

Log "Starting boot-break staging."

# Backup current BCD store for rollback.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bcdBackup = Join-Path $root "bcd-backup-$stamp.bak"
& bcdedit.exe /export $bcdBackup
if ($LASTEXITCODE -ne 0) { throw "bcdedit /export failed with code $LASTEXITCODE" }
Log "BCD backup created at $bcdBackup"

# Script that actually applies the break at startup (SYSTEM context).
$breakerScript = @'
$ErrorActionPreference = "Stop"
$log = "C:\ChaosBoot\breaker.log"

function Log([string]$m) {
    "$(Get-Date -Format s) $m" | Out-File -FilePath $log -Append -Encoding ascii
}

Log "Boot breaker started."

# Resolve active loader identifier robustly.
$guid = "{current}"
$out = & bcdedit.exe /enum "{current}" /v
if ($out -match "(?im)^\s*identifier\s+({[0-9a-fA-F-]{36}}|{current})\s*$") {
    $guid = $Matches[1]
}
Log "Target loader identifier: $guid"

# Force boot loader path to a non-existent EFI image.
& bcdedit.exe /set $guid path \Windows\System32\winload.efi.broken
if ($LASTEXITCODE -ne 0) { throw "Failed setting path on $guid, code $LASTEXITCODE" }

# Also try default entry for safety.
& bcdedit.exe /set "{default}" path \Windows\System32\winload.efi.broken 2>$null

Log "Boot break applied. Rebooting."
& shutdown.exe /r /f /t 5
'@
$breakerScript | Out-File -FilePath $breakerPath -Encoding ascii -Force
Log "Breaker script written to $breakerPath"

# Local restore script (run from recovery/serial context once you regain command access).
$restoreScript = @'
$ErrorActionPreference = "Continue"
Write-Host "Restoring loader path..."
bcdedit.exe /set {default} path \Windows\System32\winload.efi
bcdedit.exe /set {current} path \Windows\System32\winload.efi
Write-Host "If needed, import a known-good backup:"
Write-Host "  bcdedit.exe /import C:\ChaosBoot\bcd-backup-YYYYMMDD-HHMMSS.bak"
Write-Host "Done."
'@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Restore script written to $restorePath"

if ($DirectNow) {
    Log "DirectNow set. Applying break immediately."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $breakerPath
    exit 0
}

# CSE-friendly mode: schedule once at startup, then exit quickly.
& schtasks.exe /Create /TN $taskName /SC ONSTART /RU SYSTEM /RL HIGHEST /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$breakerPath`"" /F
if ($LASTEXITCODE -ne 0) { throw "Failed creating scheduled task, code $LASTEXITCODE" }
Log "Scheduled task $taskName created."

if (-not $NoReboot) {
    Log "Rebooting in 15 seconds to trigger startup task."
    & shutdown.exe /r /f /t 15
} else {
    Log "NoReboot set. Reboot manually when ready."
}

Log "Stage complete."
exit 0
