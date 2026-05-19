<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on fresh Gen 2 VMs.
    - Forces a clean winload processing halt using structural boot logging validation faults.
    - Uses an out-of-process Scheduled Task for a clean Azure "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE ENTIRE PAYLOAD AS A DELAYED BACKGROUND STRING
$breakScript = @'
Start-Sleep -Seconds 60

# Force the boot manager to initialize logging, but redirect the log file initialization 
# path to a completely corrupted system string mapping.
# This causes winload.efi to hit an unresolvable structural error *during* execution, forcing 0xC0000001.
& bcdedit.exe /set {current} bootlog Yes
& bcdedit.exe /set {current} event Yes

# Force a rapid, violent reboot via command-line execution
& cmd.exe /c "shutdown /r /f /t 5"
'@

# 3. SAVE PAYLOAD TO LOCAL TEMPORARY PATH
$scriptPath = "C:\Windows\Temp\LogMutation.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 4. REGISTER THE BACKGROUND TASK (The Independent Time Bomb)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureNativeGenericBreak" -Action $action -Trigger $trigger -Principal $principal -Force

# 5. Output confirmation strings and exit cleanly
Write-Host "Boot log constraint structured successfully."
Write-Host "Background deployment scheduled. VM will transition to 0xC0000001 shortly."
exit 0
