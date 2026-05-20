<#
    Break-Gen2Boot-0xC0000001.ps1
    Applies an unresolvable serial debugger transport speed conflict.
    Targets the exact 0xC0000001 runtime execution halt.
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

Log "Starting boot-break designed specifically for 0xC0000001 via Debug Transport Rate Mismatch."

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bcdBackup = Join-Path $root "bcd-backup-$stamp.bak"

& bcdedit.exe /export $bcdBackup
if ($LASTEXITCODE -ne 0) { throw "bcdedit /export failed" }

$currentText = (& bcdedit.exe /enum "{current}" /v | Out-String)
$m = [regex]::Match($currentText, "(?im)^\s*identifier\s+({[0-9a-fA-F-]{36}}|{current})\s*$")
if (-not $m.Success) { throw "Could not parse GUID" }
$guid = $m.Groups[1].Value

# --- CLEANUP PREVIOUS ATTEMPTS ---
& bcdedit.exe /deletevalue $guid debugtype 2>&1 | Out-Null

# --- ENFORCE SERIAL DEBUG STATE CONFLICT ---
& bcdedit.exe /set $guid recoveryenabled No 2>&1 | Out-Null
& bcdedit.exe /set $guid bootstatuspolicy DisplayAllFailures 2>&1 | Out-Null

Log "Injecting serial debugger configuration conflict..."
& bcdedit.exe /set $guid debug Yes 2>&1 | Out-Null
& bcdedit.exe /set $guid debugtype SERIAL 2>&1 | Out-Null
& bcdedit.exe /set $guid debugport 1 2>&1 | Out-Null
& bcdedit.exe /set $guid baudrate 0 2>&1 | Out-Null

# Generate local fallback script
$restoreScript = @"
Write-Host "Restoring boot environment parameters..."
bcdedit.exe /set {current} debug No
bcdedit.exe /deletevalue {current} debugtype
bcdedit.exe /deletevalue {current} debugport
bcdedit.exe /deletevalue {current} baudrate
bcdedit.exe /set {current} recoveryenabled Yes
bcdedit.exe /set {current} bootstatuspolicy IgnoreAllFailures
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force

Log "Scheduling decoupled background reboot process..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 60; & shutdown.exe /r /f /t 0"

Log "Stage complete. Script exiting cleanly."
exit 0
