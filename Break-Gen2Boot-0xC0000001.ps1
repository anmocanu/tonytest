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

if ($IUnderstand -ne "YES") {
  Write-Error "Safety check failed. Set -IUnderstand YES to proceed."
  exit 2
}

$efiDrive = "S:"
$efiBcd   = "$efiDrive\EFI\Microsoft\Boot\BCD"

Write-Output "Mounting EFI System Partition to $efiDrive ..."
cmd /c "mountvol $efiDrive /S" | Out-Null

if (!(Test-Path $efiBcd)) {
  Write-Error "EFI BCD not found at $efiBcd. Aborting."
  cmd /c "mountvol $efiDrive /D" | Out-Null
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
$bcdEnum = cmd /c "bcdedit /store $efiBcd /enum all" 2>&1
$bcdEnum | Out-String | Write-Output

# Use {default} first; if not present, fall back to {current}.
# We attempt both without branching to keep script fast/deterministic.
Write-Output "Breaking BCD entries (device/osdevice) to force Boot Manager failure..."

cmd /c "bcdedit /store $efiBcd /set {default} device unknown"        | Out-Null
cmd /c "bcdedit /store $efiBcd /set {default} osdevice unknown"      | Out-Null

cmd /c "bcdedit /store $efiBcd /set {current} device unknown"        | Out-Null
cmd /c "bcdedit /store $efiBcd /set {current} osdevice unknown"      | Out-Null

# Optional: expose the underlying boot error instead of WinRE masking.
# (Common troubleshooting practice to see the “real” boot failure code.)
cmd /c "bcdedit /store $efiBcd /set {default} recoveryenabled No"     | Out-Null
cmd /c "bcdedit /store $efiBcd /set {default} bootstatuspolicy IgnoreAllFailures" | Out-Null
cmd /c "bcdedit /store $efiBcd /set {current} recoveryenabled No"     | Out-Null
cmd /c "bcdedit /store $efiBcd /set {current} bootstatuspolicy IgnoreAllFailures" | Out-Null

Write-Output "Dismounting EFI partition ..."
cmd /c "mountvol $efiDrive /D" | Out-Null

Write-Output "Completed BCD break. VM should fail to boot on next restart (Gen2/UEFI)."

if ($ScheduleReboot -eq "YES") {
  Write-Output "Scheduling reboot in 10 seconds..."
  cmd /c "shutdown /r /f /t 10 /c ""Lab: rebooting to reproduce Gen2 BCD boot failure""" | Out-Null
} else {
  Write-Output "Reboot not scheduled. Restart manually when ready."
}

exit 0
