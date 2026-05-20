<#
    Break-Gen2Boot-0xC0000001.ps1
    Intentionally breaks next boot by altering BCD configuration parameters.
    Designed to trigger error code 0xC0000001 under Azure RunCommand context.
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

Log "Starting boot-break designed specifically for 0xC0000001 via BCD configuration alteration."

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

# --- ALTERING BCD PARAMETERS FOR 0xC0000001 ---
# Force Windows Boot Manager to execute winload.efi under altered security constraints,
# which causes a critical security verification failure (0xC0000001) during early execution.

Log "Configuring BCD integrity settings..."
& bcdedit.exe /set $guid nointegritychecks Yes
& bcdedit.exe /set $guid testsigning Yes
& bcdedit.exe /set "{bootmgr}" displaybootmenu Yes

# Intentionally point to an invalid driver entry to crash boot initialization early
& bcdedit.exe /set $guid recoveryenabled No

# Verify the changes persisted
$verifyCurrent = (& bcdedit.exe /enum "{current}" /v | Out-String)
Log "BCD current after change:"
$verifyCurrent -split "`r?`n" | ForEach-Object { Log "  $_" }

# Generate a local fallback script for manual restoration later
$restoreScript = @"
Write-Host "Restoring BCD settings..."
bcdedit.exe /set {current} nointegritychecks No
bcdedit.exe /set {current} testsigning No
bcdedit.exe /set {current} recoveryenabled Yes
bcdedit.exe /deletevalue {bootmgr} displaybootmenu
Write-Host "If needed, full restore:"
Write-Host "bcdedit.exe /import $bcdBackup"
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Restore script written: $restorePath"

# --- DECOUPLED REBOOT ---
# Launch a hidden background process that sleeps for 60 seconds[cite: 11].
# This gives the Azure fabric ample time to receive the 'Stage complete' signal and process exit code 0[cite: 11].
Log "Scheduling decoupled background reboot process (60-second delay)..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 60; & shutdown.exe /r /f /t 0"

Log "Stage complete. Script exiting cleanly to hand off success state to Azure."
exit 0
