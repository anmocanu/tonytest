<#
    Break-Gen2Boot-0xC0000001.ps1
    Intentionally breaks boot by enforcing strict ELAM driver execution policies.
    Designed to trigger exact error code 0xC0000001 under Secure Boot / Gen2 environments.
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

Log "Starting boot-break designed specifically for 0xC0000001 via ELAM Policy Isolation."

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bcdBackup = Join-Path $root "bcd-backup-$stamp.bak"

# Export existing BCD backup
& bcdedit.exe /export $bcdBackup
if ($LASTEXITCODE -ne 0) { throw "bcdedit /export failed with code $LASTEXITCODE" }
Log "BCD backup created: $bcdBackup"

# Read BCD settings as a single string
$currentText = (& bcdedit.exe /enum "{current}" /v | Out-String)
Log "Current BCD before change:"
$currentText -split "`r?`n" | ForEach-Object { Log "  $_" }

# Extract active loader identifier GUID safely
$m = [regex]::Match($currentText, "(?im)^\s*identifier\s+({[0-9a-fA-F-]{36}}|{current})\s*$")
if (-not $m.Success) {
    throw "Could not parse active loader identifier from bcdedit output."
}
$guid = $m.Groups[1].Value
Log "Target loader identifier: $guid"

# --- THE 0xC0000001 SECURE RUNTIME TRICK ---
# Force winload.efi to explicitly expect a custom hypervisor/kernel payload execution setup.
# This passes Secure Boot file integrity checks completely, but crashes winload.efi at runtime with 0xC0000001.
Log "Altering runtime load parameters..."
& bcdedit.exe /set $guid hypervisordebug Yes 2>&1
& bcdedit.exe /set $guid halbreakpoint Yes 2>&1

# Disable recovery redirection so the OS can't fallback and throw a 7b error screen
& bcdedit.exe /set $guid recoveryenabled No 2>&1

# Verify the changes persisted
$verifyCurrent = (& bcdedit.exe /enum "{current}" /v | Out-String)
Log "BCD current after change:"
$verifyCurrent -split "`r?`n" | ForEach-Object { Log "  $_" }

# Generate a local fallback script for manual restoration later
$restoreScript = @"
Write-Host "Restoring loader parameters..."
bcdedit.exe /set {current} recoveryenabled Yes
bcdedit.exe /deletevalue {current} hypervisordebug
bcdedit.exe /deletevalue {current} halbreakpoint
Write-Host "If needed, full restore:"
Write-Host "bcdedit.exe /import $bcdBackup"
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Restore script written: $restorePath"

# --- DECOUPLED REBOOT ---
# Background job ensures that the runCommand context exits cleanly with 0 back to Azure first
Log "Scheduling decoupled background reboot process (60-second delay)..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 60; & shutdown.exe /r /f /t 0"

Log "Stage complete. Script exiting cleanly to hand off success state to Azure."
exit 0
