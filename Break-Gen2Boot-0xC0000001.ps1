<#
    Break-Gen2Boot-0xC0000001.ps1
    Intentionally breaks next boot by isolating the core system configuration hive.
    Bypasses all Secure Boot / PE validation layers to cleanly trigger error code 0xC0000001.
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

Log "Starting boot-break designed specifically for 0xC0000001 via Hive Isolation."

# --- STAGE CORE REGISTRY HIVE BACKUP ---
# Instead of corrupting the boot files (which triggers format/checksum blocks), 
# we isolate the system configuration hive. This triggers 0xC0000001 during early execution initialization.
$systemHive = "C:\Windows\System32\config\SYSTEM"
$backupHive = Join-Path $root "SYSTEM.bak"

if (Test-Path $systemHive) {
    # Move the hive out of the configuration path to break execution setup cleanly
    Move-Item -Path $systemHive -Destination $backupHive -Force
    Log "Core SYSTEM configuration hive moved to staging storage: $backupHive"
} else {
    throw "Critical configuration path not located. Failed to apply breakdown parameters."
}

# Generate a local fallback script for manual restoration later
$restoreScript = @"
Write-Host "Restoring system configuration hives..."
if (Test-Path "$backupHive") {
    Move-Item -Path "$backupHive" -Destination "$systemHive" -Force
    Write-Host "SYSTEM hive restored successfully."
}
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Restore script written: $restorePath"

# --- DECOUPLED REBOOT ---
# Delays system reboot sequence to ensure the Run Command logs a success response to the ARM template first
Log "Scheduling decoupled background reboot process (60-second delay)..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 60; & shutdown.exe /r /f /t 0"

Log "Stage complete. Script exiting cleanly to hand off success state to Azure."
exit 0
