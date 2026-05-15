<#
  Break-Gen2Boot-OSBucket.ps1
  Method: Synchronous Wait + Immediate Reboot
  Goal: Success in Portal + Gen2 "No bootable device" error
#>

$ErrorActionPreference = 'Stop'

Write-Output "Starting mutation..."

# 1. Mount and Delete the Bootloader (The Mutation)
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
& cmd.exe /c "mountvol $($letter): /S"

$efiFile = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

if (Test-Path $efiFile) {
    & cmd.exe /c "takeown /f $efiFile /a"
    & cmd.exe /c "icacls $efiFile /grant administrators:F /c"
    Remove-Item -Path $efiFile -Force
    Write-Output "Success: Bootloader file removed."
}

# 2. Finalize Disk
& cmd.exe /c "mountvol $($letter): /D"

# 3. THE HANDSHAKE
# We write this to the output so Azure sees the task is 'done'.
Write-Output "Mutation complete. Reporting SUCCESS. Rebooting in 30 seconds..."

# 4. Immediate Shutdown call with a synchronous wait
# Using /t 30 gives the Azure Agent enough time to flush the logs to the platform.
& cmd.exe /c "shutdown /r /f /t 30"

# Keep the script 'Running' for 15 seconds so the Agent doesn't close the pipe too early.
Start-Sleep -Seconds 15

Write-Output "Script exiting. Reboot should follow shortly."
exit 0
