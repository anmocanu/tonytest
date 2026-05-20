<#
    Break-Gen2Boot-0xC0000001.ps1
    Intentionally breaks next boot by replacing winload with an unconfigured bootloader application.
    Designed to bypass checksum verification and trigger error code 0xC0000001 on Gen2 VMs.
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

Log "Starting boot-break designed specifically for 0xC0000001 via unconfigured loader application mapping."

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

# --- THE 0xC0000001 PURE RUNTIME EXECUTION FAIL ---
# Copy the actual unaltered Windows Boot Manager launcher binary to the path.
# This contains standard structural layout and accurate header checksum parameters (avoiding 7b and 221).
# However, launching it within a winload execution role triggers a 0xC0000001 early runtime initialization failure.
$sourceUefi = "C:\Windows\Boot\EFI\bootmgfw.efi"
$fakeLoaderPath = "C:\Windows\System32\winload.efi.broken"

Log "Copying unaltered signed UEFI loader application from $sourceUefi"
Copy-Item $sourceUefi -Destination $fakeLoaderPath -Force
Log "Pristine binary mapped to target location: $fakeLoaderPath"

# Apply the broken path to active loader
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
Log "BCD current after change:"
$verifyCurrent -split "`r?`n" | ForEach-Object { Log "  $_" }

if ($verifyCurrent -notmatch "winload\.efi\.broken") {
    throw "Verification failed: BCD does not show broken winload path."
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
# Delays system reboot sequence to ensure the Run Command logs a success response to the ARM template first
Log "Scheduling decoupled background reboot process (60-second delay)..."
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep -Seconds 60; & shutdown.exe /r /f /t 0"

Log "Stage complete. Script exiting cleanly to hand off success state to Azure."
exit 0
