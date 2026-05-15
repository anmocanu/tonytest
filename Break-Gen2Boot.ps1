<#
  Break-Gen2Boot-OSBucket.ps1
  Method: Scheduled Task (Bypasses Session Termination)
  Goal: Success in Portal + Gen2 "No bootable device" error
#>

$ErrorActionPreference = 'Stop'

# 1. Mount the EFI Partition
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
& cmd.exe /c "mountvol $($letter): /S"

$efiFile = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

# 2. Perform the Mutation (Delete the bootloader)
if (Test-Path $efiFile) {
    & cmd.exe /c "takeown /f $efiFile /a"
    & cmd.exe /c "icacls $efiFile /grant administrators:F /c"
    Remove-Item -Path $efiFile -Force
    Write-Host "Bootloader deleted successfully."
}

# 3. THE FIX: Create a "Self-Destruct" Task
# This schedules a reboot 1 minute from now using the SYSTEM account.
# Even when this script exits, the Task Scheduler will keep the countdown alive.
$taskName = "LabReboot"
$triggerTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

& cmd.exe /c "schtasks /create /tn $taskName /tr `"shutdown.exe /r /f /t 0`" /sc once /st $triggerTime /ru SYSTEM /rl HIGHEST /f"

Write-Host "Reboot scheduled for $triggerTime. Reporting success to Azure..."

# 4. Cleanup and Exit
& cmd.exe /c "mountvol $($letter): /D"
exit 0
