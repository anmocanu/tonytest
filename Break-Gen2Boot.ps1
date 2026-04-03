param(
  [string] $IUnderstand = "NO",
  [string] $ScheduleReboot = "YES"
)

if ($IUnderstand -ne "YES") {
  Write-Error "Safety check failed. Set parameter IUnderstand=YES to proceed."
  exit 2
}

$drive = "S:"
$efiFile = "$drive\EFI\Microsoft\Boot\bootmgfw.efi"
$bakFile = "$drive\EFI\Microsoft\Boot\bootmgfw.efi.bak"

Write-Output "Mounting EFI System Partition to $drive ..."
cmd /c "mountvol $drive /S" | Out-String | Write-Output

if (!(Test-Path $efiFile)) {
  Write-Error "EFI bootloader not found at $efiFile. Nothing changed."
  cmd /c "mountvol $drive /D" | Out-String | Write-Output
  exit 3
}

if (Test-Path $bakFile) {
  Write-Output "Backup already exists ($bakFile). Overwriting it."
  Remove-Item -Force $bakFile
}

Write-Output "Renaming bootloader to break boot on next restart:"
Write-Output "  $efiFile -> $bakFile"
Rename-Item -Path $efiFile -NewName (Split-Path $bakFile -Leaf) -Force

Write-Output "Dismounting EFI System Partition ..."
cmd /c "mountvol $drive /D" | Out-String | Write-Output

Write-Output "Completed. VM will fail to boot after restart (Gen2/UEFI)."

if ($ScheduleReboot -eq "YES") {
  Write-Output "Scheduling reboot in 15 seconds..."
  cmd /c "shutdown /r /t 15 /c ""LabBox: rebooting to reproduce Gen2 boot failure""" | Out-String | Write-Output
} else {
  Write-Output "Reboot not scheduled. Restart manually when ready."
}
