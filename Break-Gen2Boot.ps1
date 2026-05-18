<#
  Break-Gen2Boot-OSBucket.ps1
  Scenario: OS Bucket / Boot Failure (Gen2)
  Strategy: [BAT/POWERSHELL] Background Logic + Recursive EFI Destruction
  Goal: Ensure "No bootable device found" error persists after reboot.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately 
# This ensures the script doesn't hang on the Diagnostic Data screen.
Write-Output "Clearing OOBE blocking processes..."
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE DESTRUCTION PAYLOAD
# We use a script block to ensure all destructive commands run in a single background thread.
$breakScript = @"
Start-Sleep -Seconds 60

# Mount the EFI System Partition
& cmd.exe /c "mountvol S: /S"

# Define the target folders for total destruction
# Targeting the entire Microsoft folder prevents the UEFI from finding backup BCD or EFI files.
`$targetFolder = "S:\EFI\Microsoft"
`$fallbackFile = "S:\EFI\Boot\bootx64.efi"

if (Test-Path `$targetFolder) {
    # Strip Read-Only, System, and Hidden attributes recursively
    & cmd.exe /c "attrib -r -s -h S:\EFI\Microsoft\* /s /d"
    
    # Force delete the entire Microsoft boot hierarchy
    Remove-Item -Path `$targetFolder -Recurse -Force
}

if (Test-Path `$fallbackFile) {
    & cmd.exe /c "attrib -r -s -h `$fallbackFile"
    Remove-Item -Path `$fallbackFile -Force
}

# Unmount and trigger a "Violent" reboot via shutdown.exe
& cmd.exe /c "mountvol S: /D"
& cmd.exe /c "shutdown /r /f /t 5"
"@

# 3. SAVE PAYLOAD TO LOCAL DISK
$scriptPath = "C:\Windows\Temp\FinalMutation.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 4. REGISTER THE BACKGROUND TASK (The "Time Bomb")
# This ensures the script survives after the Azure Run Command reports success.
Write-Output "Registering background Scheduled Task..."

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureLabBreak" -Action $action -Trigger $trigger -Principal $principal -Force

# 5. REPORT SUCCESS TO AZURE
# Display task status for the logs before exiting
Get-ScheduledTask -TaskName "AzureLabBreak" | Select-Object TaskName, State

Write-Output "Success reported. The VM will self-destruct and reboot in approximately 90 seconds."
exit 0
