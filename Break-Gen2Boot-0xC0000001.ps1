<#
    Break-Gen2Boot-0xC0000001.ps1
    Intentionally restricts boot initialization by supplying an invalid custom HAL name.
    Designed to trigger the exact error code 0xC0000001 on Gen2 / Trusted Launch VMs.
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

Log "Starting boot-break designed specifically for 0xC0000001 via HAL Diversion Mapping."

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

# --- THE DEFINITIVE HAL MAPPING TRICK ---
# Clean up experimental parameters from previous iterations
& bcdedit.exe /deletevalue $guid testsigning 2>&1 | Out-Null
& bcdedit.exe /deletevalue $guid nointegritychecks 2>&1 | Out-Null

# Force recovery options to stay disabled so the error is explicitly surfaced
& bcdedit.exe /set $guid recoveryenabled No 2>&1 | Out-Null
& bcdedit.exe /set $guid bootstatuspolicy DisplayAllFailures 2>&1 | Out-Null

# Inject an invalid custom HAL file parameter string.
# This passes pre-flight checks but completely breaks the execution loop with 0xC0000001.
Log "Configuring invalid HAL file target variable..."
& bcdedit.exe /set $guid hal "chaos_hal.dll" 2>&1 | Out-Null

# Verify the changes persisted
$verifyCurrent = (& bcdedit.exe /enum "{current}" /v | Out-String)
Log "BCD current after change:"
$verifyCurrent -split "`r?`n" | ForEach-Object { Log "  $_" }

# Generate a local fallback script for manual restoration later
$restoreScript = @"
Write-Host "Restoring boot environment parameters..."
bcdedit.exe /deletevalue {current} hal
bcdedit.exe /set {current} recoveryenabled Yes
bcdedit.exe /set {current} bootstatuspolicy IgnoreAllFailures
Write-Host "If needed, full restore:"
Write-Host "bcdedit.exe /import $bcdBackup"
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Restore script written: $restorePath"

# --- DECOUPLED REBOOT ---
Log "Scheduling decoupled background reboot process (60-second delay)..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 60; & shutdown.exe /r /f /t 0"

Log "Stage complete. Script exiting cleanly to hand off success state to Azure."
exit 0
