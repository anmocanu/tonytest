<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on fresh Gen 2 VMs.
    - Breaks the boot loader execution sequence via an invalid driver dependency group.
    - Uses an out-of-process Scheduled Task for a clean Azure "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE ENTIRE PAYLOAD AS A DELAYED BACKGROUND STRING
$breakScript = @'
Start-Sleep -Seconds 60

# Target a fundamental system group dependency (Wof - Windows Overlay Filter)
# Changing its Group designation to a non-existent group breaks winload's internal load-order tree.
# This forces a clean structural halt resulting in a 0xC0000001 screen, while leaving files perfectly intact.
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Wof" -Name "Group" -Value "DoesNotExistGroup" -Force

# Force a rapid, violent reboot via command-line execution
& cmd.exe /c "shutdown /r /f /t 5"
'@

# 3. SAVE PAYLOAD TO LOCAL TEMPORARY PATH
$scriptPath = "C:\Windows\Temp\DependencyMutation.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 4. REGISTER THE BACKGROUND TASK (The Independent Time Bomb)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureNativeGenericBreak" -Action $action -Trigger $trigger -Principal $principal -Force

# 5. Output confirmation strings and exit cleanly
Write-Host "Driver dependency constraint structured successfully."
Write-Host "Background deployment scheduled. VM will transition to 0xC0000001 shortly."
exit 0
