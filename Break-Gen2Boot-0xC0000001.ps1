<#
    Break-Gen2Boot-0xC0000001.ps1
    Uses Volume Shadow Copy to extract and modify the boot hive structure.
    Guaranteed to bypass file-lock controls and surface 0xC0000001 under Gen2.
#>

$ErrorActionPreference = "Stop"

$root = "C:\ChaosBoot"
$logPath = Join-Path $root "stage.log"
$restorePath = Join-Path $root "Restore-Boot.ps1"

New-Item -ItemType Directory -Path $root -Force | Out-Null

function Log([string]$msg) {
    $line = "$(Get-Date -Format s) $msg"
    $line | Out-File -FilePath $logPath -Append -Encoding ascii
    Write-Host $line
}

Log "Starting boot-break designed specifically for 0xC0000001 via Shadow Hive Modification."

# 1. Clean up BCD modifications to ensure pre-flight checks pass cleanly
& bcdedit.exe /set {current} recoveryenabled No 2>&1 | Out-Null
& bcdedit.exe /set {current} bootstatuspolicy DisplayAllFailures 2>&1 | Out-Null

# 2. Extract the locked SYSTEM hive using Volume Shadow Copy
Log "Creating volume shadow copy snapshot..."
$vssScript = "vssadmin.exe create shadow /for=C:"
$vssOutput = Invoke-Expression $vssScript | Out-String

# Parse the shadow copy volume path (e.g., \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopyX)
$shadowPathMatch = [regex]::Match($vssOutput, '(?im)Shadow Copy Volume Name:\s+(\\\\[^\s]+)')
if (-not $shadowPathMatch.Success) {
    throw "Failed to capture Volume Shadow Copy snapshot."
}
$shadowVolume = $shadowPathMatch.Groups[1].Value
Log "Shadow volume created successfully at: $shadowVolume"

# 3. Copy the hive file out of the shadow snapshot context
$stagedHive = Join-Path $root "SYSTEM.staged"
$backupHive = Join-Path $root "SYSTEM.bak"
$shadowSystemHivePath = "$shadowVolume\Windows\System32\config\SYSTEM"

Log "Extracting boot database from snapshot context..."
cmd.exe /c copy `"$shadowSystemHivePath`" `"$stagedHive`" | Out-Null
cmd.exe /c copy `"$shadowSystemHivePath`" `"$backupHive`" | Out-Null

# 4. Modify the staged hive structure to break initialization parameters
Log "Stripping critical boot target mappings from the staged database..."
& reg.exe load "HKLM\ChaosTarget" $stagedHive 2>&1 | Out-Null
# Deleting the Select key removes the pointers to CurrentControlSet, making it unbootable
& reg.exe delete "HKLM\ChaosTarget\Select" /f 2>&1 | Out-Null
& reg.exe unload "HKLM\ChaosTarget" 2>&1 | Out-Null

# 5. Stage the replacement operation to happen during the restart sequence
Log "Registering hive file replacement transaction..."
$registryKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
$existingSessionOperations = Get-ItemProperty -Path $registryKeyPath -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue

[string[]]$newSessionOperations = @()
if ($existingSessionOperations) {
    $newSessionOperations += $existingSessionOperations.PendingFileRenameOperations
}
$newSessionOperations += "\??\$stagedHive"
$newSessionOperations += "\??\C:\Windows\System32\config\SYSTEM"

Set-ItemProperty -Path $registryKeyPath -Name "PendingFileRenameOperations" -Value $newSessionOperations

# 6. Generate the recovery script to restore the environment later if required
$restoreScript = @"
Write-Host "Reinstating original production hive tracking configurations..."
if (Test-Path "$backupHive") {
    Copy-Item -Path "$backupHive" -Destination "C:\Windows\System32\config\SYSTEM" -Force
    Write-Host "System configuration restored successfully."
}
bcdedit.exe /set {current} recoveryenabled Yes
bcdedit.exe /set {current} bootstatuspolicy IgnoreAllFailures
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Recovery script saved locally at: $restorePath"

# --- DECOUPLED REBOOT ---
Log "Scheduling system restart process..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 15; & shutdown.exe /r /f /t 0"

Log "Stage complete. Script exiting cleanly."
exit 0
