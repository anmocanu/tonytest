<#
    Break-Gen2Boot-0xC0000001.ps1
    Intentionally breaks next boot by changing winload path to an invalid binary payload.
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

Log "Starting boot-break designed specifically for 0xC0000001."

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bcdBackup = Join-Path $root "bcd-backup-$stamp.bak"

# Export existing BCD backup [cite: 1]
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

# --- REMEDIAL PAYLOAD FOR 0xC0000001 ---
# Instead of a plain text string (which triggers 0xc000007b), we provide a 
# pseudo-binary structure that passes basic format parsing but crashes on execution signature checks.
$fakeLoaderPath = "C:\Windows\System32\winload.efi.broken"

# Start with a standard MZ PE header signature to satisfy the image format check
[byte[]]$pePayload = @(0x4d, 0x5a, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00) 
# Pad out the file with empty execution structures
$pePayload += ,0x00 * 500 

[System.IO.File]::WriteAllBytes($fakeLoaderPath, $pePayload)
Log "PE-masked dummy file generated at $fakeLoaderPath"

# Apply the broken path to active loader [cite: 1]
$out1 = & bcdedit.exe /set $guid path \Windows\System32\winload.efi.broken 2>&1
$code1 = $LASTEXITCODE
Log "Set path on $guid exit code: $code1"
if ($out1) { $out1 | ForEach-Object { Log "  $_" } }
if ($code1 -ne 0) { throw "Failed setting path on $guid" }

# Apply the broken path to default entry as well
$out2 = & bcdedit.exe /set "{default}" path \Windows\System32\winload.efi.broken 2>&1
$code2 = $LASTEXITCODE
Log "Set path on {default} exit code: $code2"
if ($out2) { $out2 | ForEach-Object { Log "  $_" } }

# Verify the changes persisted
$verifyCurrent = (& bcdedit.exe /enum "{current}" /v | Out-String)
$verifyDefault = (& bcdedit.exe /enum "{default}" /v | Out-String)
Log "BCD current after change:"
$verifyCurrent -split "`r?`n" | ForEach-Object { Log "  $_" }
Log "BCD default after change:"
$verifyDefault -split "`r?`n" | ForEach-Object { Log "  $_" }

if (($verifyCurrent -notmatch "winload\.efi\.broken") -and ($verifyDefault -notmatch "winload\.efi\.broken")) {
    throw "Verification failed: neither {current} nor {default} shows broken winload path."
}

# Generate a local fallback script for manual restoration later
$restoreScript = @"
Write-Host "Restoring loader paths..."
if (Test-Path "$fakeLoaderPath") { Remove-Item "$fakeLoaderPath" -Force }
bcdedit.exe /set {current} path \Windows\System32\winload.efi
bcdedit.exe /set {default} path \Windows\System32\winload.efi
Write-Host "If needed, full restore:"
Write-Host "bcdedit.exe /import $bcdBackup"
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Restore script written: $restorePath"

# --- DECOUPLED REBOOT ---
# Launch a hidden background process that sleeps for 60 seconds[cite: 1].
# This gives the Azure fabric ample time to receive the 'Stage complete' signal and process exit code 0[cite: 1].
Log "Scheduling decoupled background reboot process (60-second delay)..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 60; & shutdown.exe /r /f /t 0"

Log "Stage complete. Script exiting cleanly to hand off success state to Azure."
exit 0
