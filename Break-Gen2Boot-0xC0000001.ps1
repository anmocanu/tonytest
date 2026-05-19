<#
.SYNOPSIS
  Applies boot break immediately before shutdown (ARM CSE-friendly).

.DESCRIPTION
  - Applies BCD changes synchronously before triggering reboot.
  - Ensures break is in place when bootloader reads BCD.
  - Creates restore artifacts for recovery.

.NOTES
  This makes the VM unbootable until restored.
#>

$ErrorActionPreference = 'Stop'

$root = 'C:\ChaosBoot'
$logPath = Join-Path $root 'stage.log'
$restorePath = Join-Path $root 'Restore-Boot.ps1'

New-Item -ItemType Directory -Path $root -Force | Out-Null

function Log([string]$msg) {
    $line = "$(Get-Date -Format s) $msg"
    $line | Out-File -FilePath $logPath -Append -Encoding ascii
    Write-Host $line
}

Log "Starting boot-break (immediate mode)."

# Backup BCD for rollback.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bcdBackup = Join-Path $root "bcd-backup-$stamp.bak"
& bcdedit.exe /export $bcdBackup
if ($LASTEXITCODE -ne 0) { throw "bcdedit /export failed with code $LASTEXITCODE" }
Log "BCD backup created: $bcdBackup"

# Enumerate and log current BCD state.
$currentBCD = & bcdedit.exe /enum "{current}" /v
Log "Current BCD before change:"
$currentBCD | ForEach-Object { Log "  $_" }

# Get the GUID of the currently booted loader.
$guid = "{current}"
if ($currentBCD -match "identifier\s+({[a-fA-F0-9-]{36}}|{current})") {
    $guid = $Matches[1]
}
Log "Target loader GUID: $guid"

# Apply the break NOW, synchronously, before reboot.
Log "Applying boot break to path..."
& bcdedit.exe /set $guid path "\Windows\System32\winload.efi.broken"
$exitCode = $LASTEXITCODE
Log "bcdedit /set {$guid} path - exit code: $exitCode"

if ($exitCode -ne 0) {
    throw "Failed to set path. Exit code: $exitCode"
}

# Also try {default} to cover both.
& bcdedit.exe /set "{default}" path "\Windows\System32\winload.efi.broken" 2>$null
Log "bcdedit /set {default} path - exit code: $?"

# Verify the change took effect.
$postBCD = & bcdedit.exe /enum "{current}" /v
Log "BCD after change:"
$postBCD | ForEach-Object { Log "  $_" }

# Create restore script.
$restoreScript = @"
Write-Host "Restoring winload.efi paths..."
bcdedit.exe /set {default} path "\Windows\System32\winload.efi"
bcdedit.exe /set {current} path "\Windows\System32\winload.efi"
Write-Host "To restore from backup:"
Write-Host "  bcdedit.exe /import $bcdBackup"
Write-Host "Done."
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Restore script written: $restorePath"

Log "Boot break applied. Rebooting in 10 seconds..."
& shutdown.exe /r /f /t 10

Log "Stage complete."
exit 0
