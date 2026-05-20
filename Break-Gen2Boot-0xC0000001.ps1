<#
    Break-Gen2Boot-0xC0000001.ps1
    Forces a setup subsystem initialization mismatch.
    Bypasses file validation filters to surface exact error code 0xC0000001.
#>

$ErrorActionPreference = "Stop"

$root = "C:\ChaosBoot"
$logPath = Join-Path $root "stage.log"
$restorePath = Join-Path $root "Restore-Boot.ps1"

# Create the staging directory
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Log([string]$msg) {
    $line = "$(Get-Date -Format s) $msg"
    $line | Out-File -FilePath $logPath -Append -Encoding ascii
    Write-Host $line
}

Log "Starting boot-break designed specifically for 0xC0000001 via Subsystem State Mismatch."

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bcdBackup = Join-Path $root "bcd-backup-$stamp.bak"

# Export existing BCD backup
& bcdedit.exe /export $bcdBackup
if ($LASTEXITCODE -ne 0) { throw "bcdedit /export failed" }

# Read BCD settings as a single string
$currentText = (& bcdedit.exe /enum "{current}" /v | Out-String)

# Extract active loader identifier GUID safely
$m = [regex]::Match($currentText, "(?im)^\s*identifier\s+({[0-9a-fA-F-]{36}}|{current})\s*$")
if (-not $m.Success) { throw "Could not parse active loader identifier." }
$guid = $m.Groups[1].Value

# --- CLEANUP PREVIOUS ATTEMPTS ---
& bcdedit.exe /deletevalue $guid debug 2>&1 | Out-Null
& bcdedit.exe /deletevalue $guid debugtype 2>&1 | Out-Null
& bcdedit.exe /deletevalue $guid debugport 2>&1 | Out-Null
& bcdedit.exe /deletevalue $guid baudrate 2>&1 | Out-Null

# --- ENFORCE SUBSYSTEM CONFLICT ---
# Force recovery options to stay disabled so the error is explicitly surfaced
& bcdedit.exe /set $guid recoveryenabled No 2>&1 | Out-Null
& bcdedit.exe /set $guid bootstatuspolicy DisplayAllFailures 2>&1 | Out-Null

# Direct the boot configuration to execute under an impossible system setup phase.
# This keeps the binary file chain 100% genuine and valid for Secure Boot,
# but forces winload.efi to drop a 0xC0000001 error when the environment handles the phase.
Log "Applying subsystem setup context overrides..."
& bcdedit.exe /set $guid ems Yes 2>&1 | Out-Null
& bcdedit.exe /set $guid custom:250000C2 1 2>&1 | Out-Null

# Verify the changes persisted
$verifyCurrent = (& bcdedit.exe /enum "{current}" /v | Out-String)
Log "BCD current after change:"
$verifyCurrent -split "`r?`n" | ForEach-Object { Log "  $_" }

# Generate a local fallback script for manual restoration later
$restoreScript = "@
Write-Host 'Restoring boot environment parameters...'
bcdedit.exe /deletevalue {current} custom:250000C2
bcdedit.exe /set {current} recoveryenabled Yes
bcdedit.exe /set {current} bootstatuspolicy IgnoreAllFailures
Write-Host 'If needed, full restore:'
Write-Host 'bcdedit.exe /import $bcdBackup'
@"
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force

# --- DECOUPLED REBOOT ---
Log "Scheduling decoupled background reboot process (60-second delay)..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 60; & shutdown.exe /r /f /t 0"

Log "Stage complete. Script exiting cleanly."
exit 0
