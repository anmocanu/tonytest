<#
Break-Gen2Boot-0xC0000001-BCDEdit.ps1

Purpose:
- Gen2/UEFI: break boot via EFI BCD store edits (no ACL/takeown; no raw file writes)
- Designed for Azure RunCommand (fast + deterministic)
#>

param(
  [string]$IUnderstand = "NO",
  [string]$ScheduleReboot = "YES"
)

$ErrorActionPreference = "Stop"

function Invoke-CmdChecked {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [switch]$AllowFailure
  )

  $output = cmd /c $Command 2>&1
  $code = $LASTEXITCODE

  if (-not $AllowFailure -and $code -ne 0) {
    throw "Command failed (exit $code): $Command`n$output"
  }

  return $output
}

function Get-OsLoaderIdentifier {
  param([Parameter(Mandatory = $true)][string]$StorePath)

  $enum = Invoke-CmdChecked -Command "bcdedit /store $StorePath /enum all"
  $blocks = ($enum -join "`n") -split "`r?`n`r?`n"

  foreach ($block in $blocks) {
    if ($block -match "Windows Boot Loader" -and $block -match "path\s+\\Windows\\system32\\winload\.efi") {
      $idLine = ($block -split "`r?`n" | Where-Object { $_ -match "^identifier\s+" } | Select-Object -First 1)
      if ($idLine -and $idLine -match "identifier\s+(\{[^\}]+\})") {
        return $matches[1]
      }
    }
  }

  return $null
}

if ($IUnderstand -ne "YES") {
  Write-Error "Safety check failed. Set -IUnderstand YES to proceed."
  exit 2
}

$efiDrive = "S:"
$efiBcd   = "$efiDrive\EFI\Microsoft\Boot\BCD"

Write-Output "Mounting EFI System Partition to $efiDrive ..."
Invoke-CmdChecked -Command "mountvol $efiDrive /S" | Out-Null

if (!(Test-Path $efiBcd)) {
  Write-Error "EFI BCD not found at $efiBcd. Aborting."
  Invoke-CmdChecked -Command "mountvol $efiDrive /D" -AllowFailure | Out-Null
  exit 3
}

Write-Output "Backing up EFI BCD (best effort) ..."
try {
  Copy-Item -Path $efiBcd -Destination "$efiBcd.bak" -Force
  Write-Output "Backup created: $efiBcd.bak"
} catch {
  Write-Output "Backup copy failed (continuing): $($_.Exception.Message)"
}

# IMPORTANT: Use BCDEdit to modify the EFI BCD store (no raw writes; FAT32 has no ACLs).
Write-Output "Enumerating current loader identifier (expect {default} or {current}) ..."
$bcdEnum = Invoke-CmdChecked -Command "bcdedit /store $efiBcd /enum all"
$bcdEnum | Out-String | Write-Output

Write-Output "Discovering active Windows Boot Loader identifier from EFI store ..."
$loaderId = Get-OsLoaderIdentifier -StorePath $efiBcd
if (-not $loaderId) {
  Write-Error "Could not find Windows Boot Loader identifier in EFI BCD store."
  Invoke-CmdChecked -Command "mountvol $efiDrive /D" -AllowFailure | Out-Null
  exit 4
}
Write-Output "Resolved loader identifier: $loaderId"

Write-Output "Applying boot-fatal but syntactically valid BCD mutations ..."

# Use a non-existent partition so BCDEdit accepts the value, but boot cannot locate OS volume.
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId device partition=Z:" | Out-Null
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId osdevice partition=Z:" | Out-Null

# Add an independent failure mode to avoid successful fallback.
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId systemroot \Windows_BROKEN" | Out-Null

# Optional: expose the underlying boot error instead of WinRE masking.
# (Common troubleshooting practice to see the “real” boot failure code.)
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId recoveryenabled No" | Out-Null
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /set $loaderId bootstatuspolicy IgnoreAllFailures" | Out-Null

Write-Output "Post-mutation BCD snapshot:"
Invoke-CmdChecked -Command "bcdedit /store $efiBcd /enum $loaderId" | Out-String | Write-Output

Write-Output "Dismounting EFI partition ..."
Invoke-CmdChecked -Command "mountvol $efiDrive /D" | Out-Null

Write-Output "Completed BCD break. VM should fail to boot on next restart (Gen2/UEFI)."

if ($ScheduleReboot -eq "YES") {
  Write-Output "Scheduling reboot in 10 seconds..."
  cmd /c "shutdown /r /f /t 10 /c ""Lab: rebooting to reproduce Gen2 BCD boot failure""" | Out-Null
} else {
  Write-Output "Reboot not scheduled. Restart manually when ready."
}

exit 0
