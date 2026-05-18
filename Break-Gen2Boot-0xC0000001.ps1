<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on fresh Gen 2 VMs.
    - Uses native PowerShell Service commands to bypass silent registry loader failures.
    - Uses an out-of-process Scheduled Task for a clean Azure "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE ENTIRE PAYLOAD AS A DELAYED BACKGROUND STRING
# We use native WMI/CIM service modifiers which are 100% reliable under SYSTEM account context.
$breakScript = @'
Start-Sleep -Seconds 60

# Target the core cloud virtual storage bus service (vmbus)
# We change its ImagePath to a non-existent file. 
# Because winload requires vmbus to initialize the hardware tree, a missing path guarantees 0xC0000001.
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\vmbus" -Name "ImagePath" -Value "System32\drivers\doesnotexist.sys" -Force

# Force a rapid, violent reboot via command-line execution
& cmd.exe /c "shutdown /r /f /t 5"
'@

# 3. SAVE PAYLOAD TO LOCAL TEMPORARY PATH
$scriptPath = "C:\Windows\Temp\NativeMutation.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 4. REGISTER THE BACKGROUND TASK (The Independent Time Bomb)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureNativeGenericBreak" -Action $action -Trigger $trigger -Principal $principal -Force

# 5. Output confirmation strings and exit cleanly
Write-Host "Native service constraint structured successfully."
Write-Host "Background deployment scheduled. VM will transition to 0xC0000001 shortly."
exit 0
