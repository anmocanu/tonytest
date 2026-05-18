<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) for training labs.
    - Prevents VMAgentStatusCommunicationError by moving all logic to a delayed task.
    - Uses an out-of-process Scheduled Task for a clean Azure "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE ENTIRE PAYLOAD AS A DELAYED BACKGROUND STRING
# Every single command that alters the system state must live inside here.
$breakScript = @'
Start-Sleep -Seconds 60

# Force the Boot Manager into a generic configuration initialization failure
# By pointing the path of the boot debugger to a non-existent file, winload throws 0xC0000001
& bcdedit.exe /set {current} bootdebug Yes
& bcdedit.exe /set {current} debugpath "\Windows\System32\drivers\doesnotexist.sys"

# Force a rapid, violent reboot via command-line execution
& cmd.exe /c "shutdown /r /f /t 5"
'@

# 3. SAVE PAYLOAD TO LOCAL TEMPORARY PATH
$scriptPath = "C:\Windows\Temp\BcdMutation.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 4. REGISTER THE BACKGROUND TASK (The Independent Time Bomb)
# Running this as SYSTEM with a 1-minute buffer lets the Guest Agent cleanly
# finish reporting its status back to the Azure fabric before the OS configuration shifts.
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureBCDGenericBreak" -Action $action -Trigger $trigger -Principal $principal -Force

# 5. Output confirmation strings and exit cleanly
Write-Host "BCD configuration route structured successfully."
Write-Host "Background deployment scheduled. VM will halt with 0xC0000001 on next boot phase."
exit 0
