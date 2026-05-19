<#
  Break-Gen2Boot-Immediate.ps1
  Intentionally breaks next boot by changing winload path.
  Designed for Azure RunCommand context.
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

Log "Starting boot-break (immediate mode)."

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bcdBackup = Join-Path $root "bcd-backup-$stamp.bak"

& bcdedit.exe /export $bcdBackup
if ($LASTEXITCODE -ne 0) { throw "bcdedit /export failed with code $LASTEXITCODE" }
Log "BCD backup created: $bcdBackup"

# Read as single string so regex groups are reliable.
$currentText = (& bcdedit.exe /enum "{current}" /v | Out-String)
Log "Current BCD before change:"
$currentText -split "`r?`n" | ForEach-Object { Log "  $_" }

# Robust GUID extraction without using automatic $Matches from collection matching.
$m = [regex]::Match($currentText, "(?im)^\s*identifier\s+({[0-9a-fA-F-]{36}}|{current})\s*$")
if (-not $m.Success) {
    throw "Could not parse active loader identifier from bcdedit output."
}
$guid = $m.Groups[1].Value
Log "Target loader identifier: $guid"

# Apply break to active loader.
$out1 = & bcdedit.exe /set $guid path \Windows\System32\winload.efi.broken 2>&1
$code1 = $LASTEXITCODE
Log "Set path on $guid exit code: $code1"
if ($out1) { $out1 | ForEach-Object { Log "  $_" } }
if ($code1 -ne 0) { throw "Failed setting path on $guid" }

# Apply break to default entry as well.
$out2 = & bcdedit.exe /set "{default}" path \Windows\System32\winload.efi.broken 2>&1
$code2 = $LASTEXITCODE
Log "Set path on {default} exit code: $code2"
if ($out2) { $out2 | ForEach-Object { Log "  $_" } }

# Verify persisted change.
$verifyCurrent = (& bcdedit.exe /enum "{current}" /v | Out-String)
$verifyDefault = (& bcdedit.exe /enum "{default}" /v | Out-String)
Log "BCD current after change:"
$verifyCurrent -split "`r?`n" | ForEach-Object { Log "  $_" }
Log "BCD default after change:"
$verifyDefault -split "`r?`n" | ForEach-Object { Log "  $_" }

if (($verifyCurrent -notmatch "winload\.efi\.broken") -and ($verifyDefault -notmatch "winload\.efi\.broken")) {
    throw "Verification failed: neither {current} nor {default} shows broken winload path."
}

$restoreScript = @"
Write-Host "Restoring loader paths..."
bcdedit.exe /set {current} path \Windows\System32\winload.efi
bcdedit.exe /set {default} path \Windows\System32\winload.efi
Write-Host "If needed, full restore:"
Write-Host "bcdedit.exe /import $bcdBackup"
"@
$restoreScript | Out-File -FilePath $restorePath -Encoding ascii -Force
Log "Restore script written: $restorePath"

Log "Break applied. Rebooting in 15 seconds."
& shutdown.exe /r /f /t 15

Log "Stage complete."
exit 0
