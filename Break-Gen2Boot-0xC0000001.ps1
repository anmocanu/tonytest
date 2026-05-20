<#
    Break-Gen2Boot-0xC0000001.ps1
    Simulates a critical subsystem initialization failure.
    Forces winload.efi to surface an authentic 0xC0000001 status screen under Gen2 rules.
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

Log "Starting boot-break designed specifically for 0xC0000001 via Subsystem Hive Isolation."

# Target critical boot initialization database paths
$systemHive = "C:\Windows\System32\config\SYSTEM"
$hiveBackup = Join-Path $root "SYSTEM.bak"

# 1. Clean up any lingering BCD flags from prior test phases
Log "Resetting BCD options to default production states..."
$currentText = (& bcdedit.exe /enum "{current}" /v | Out-String)
$m = [regex]::Match($currentText, "(?im)^\s*identifier\s+({[0-9a-fA-F-]{36}}|{current})\s*$")
if ($m.Success) {
    $guid = $m.Groups[1].Value
    & bcdedit.exe /deletevalue $guid debug 2>&1 | Out-Null
    & bcdedit.exe /deletevalue $guid debugtype 2>&1 | Out-Null
    & bcdedit.exe /deletevalue $guid debugport 2>&1 | Out-Null
    & bcdedit.exe /deletevalue $guid baudrate 2>&1 | Out-Null
    & bcdedit.exe /deletevalue $guid custom:250000C2 2>&1 | Out-Null
}

# Ensure recovery UI redirection is off so the error screen is cleanly visible
& bcdedit.exe /set {current} recoveryenabled No 2>&1 | Out-Null
& bcdedit.exe /set {current} bootstatuspolicy DisplayAllFailures 2>&1 | Out-Null

# 2. Take a secure backup of the operational SYSTEM configuration hive
if (-not (Test-Path $hiveBackup)) {
    Log "Creating backup of the live SYSTEM hive configuration..."
    Copy-Item -Path $systemHive -Destination $hiveBackup -Force
}

# 3. Use the native registry engine to generate a structurally valid, completely blank dummy database file
Log "Generating uninitialized database template..."
$tmpHivePath = Join-Path $root "BLANK_HIVE"
if (Test-Path $tmpHivePath) { Remove-Item $tmpHivePath -Force }

# Initialize a clean, empty structure context using a temporary mounting sequence
& reg.exe save "HKLM\SAM" $tmpHivePath 2>&1 | Out-Null

# 4. Safely swap out the production hive file.
# Note: The active SYSTEM hive is locked by the running OS instance. 
# We stage a native file move transaction that executes immediately upon system restart.
Log "Registering early boot system hive substitution..."
$cmd = "cmd.exe /c move /y `"$tmpHivePath`" `"$systemHive`""
$registryKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
$existingSessionOperations = Get-ItemProperty -Path $registryKeyPath -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue

[string[]]$newSessionOperations = @()
if ($existingSessionOperations) {
    $newSessionOperations += $existingSessionOperations.PendingFileRenameOperations
}
# Prepend custom database path mappings to the boot-rename buffer
$newSessionOperations += "\??\$tmpHivePath"
$newSessionOperations += "\??\$systemHive"

Set-ItemProperty -Path $registryKeyPath -Name "PendingFileRenameOperations" -Value $newSessionOperations

# 5. Generate a recovery fallback automation payload
$restoreScript = @"
Write-Host "Reinstating valid production hive environment..."
if (Test-Path "$hiveBackup") {
    Copy-Item -Path "$hiveBackup" -Destination "$systemHive" -Force
    Write-Host "System configuration successfully restored."
} else {
    Write-Warning "Backup file not found at $hiveBackup"
}
bcdedit.exe /set {current} recoveryenabled Yes
bcdedit.exe /set {current} bootstatuspolicy IgnoreAllFailures
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Recovery workflow saved locally: $restorePath"

# --- DECOUPLED REBOOT ---
Log "Scheduling system restart process..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 15; & shutdown.exe /r /f /t 0"

Log "Stage complete. Handoff to target failure framework active."
exit 0
