<#
  Break-Gen2Boot-OSBucket.ps1
  Method: Native PowerShell Scheduled Task
  Goal: Success in Portal + Gen2 "No bootable device" error
#>

$ErrorActionPreference = 'Stop'

# 1. Mount and Delete the Bootloader (The Mutation)
$usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
$letter = ('S','Y','Z','T','U','V') | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
mountvol "$($letter):" /S

$efiFile = "$($letter):\EFI\Microsoft\Boot\bootmgfw.efi"

if (Test-Path $efiFile) {
    takeown /f $efiFile /a
    icacls $efiFile /grant administrators:F /c
    Remove-Item -Path $efiFile -Force
    Write-Host "Success: Bootloader deleted."
}

mountvol "$($letter):" /D

# 2. Create the Scheduled Task using Native Cmdlets
# This avoids the "cmd /c" pathing issues.
$taskName = "LabReboot"
$action = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument "/r /f /t 0"
# Set trigger for 1 minute from now
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
# Run as SYSTEM for highest privilege
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType Service -RunLevel Highest

Write-Host "Registering the scheduled task..."
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal

Write-Host "Task registered. Reporting success to Azure. VM reboots in 60s."
exit 0
