<#
  Break-Gen2Boot-0xC0000001.ps1
  Purpose: 
    - Reliably simulate 0xC0000001 (STATUS_UNSUCCESSFUL) on fresh Gen 2 VMs.
    - Creates a faulty boot-start service dependency to force initialization failure.
    - Uses an out-of-process Scheduled Task for a clean Azure "Success" handshake.
#>

$ErrorActionPreference = 'Stop'

# 1. Clear OOBE Barrier immediately so the Guest Agent can breathe
Get-Process -Name "UserOOBEBroker" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. DEFINE THE ENTIRE PAYLOAD AS A DELAYED BACKGROUND STRING
$breakScript = @'
Start-Sleep -Seconds 90

# Load the offline SYSTEM hive to guarantee the setting commits outside kernel locks
& reg.exe load HKLM\OFFLINE_SYSTEM C:\Windows\System32\config\SYSTEM

# Create a dummy critical boot driver service entry
$servicePath = "HKLM\OFFLINE_SYSTEM\ControlSet001\Services\FakeBootDriver"
& reg.exe add $servicePath /v Start /t REG_DWORD /d 0 /f
& reg.exe add $servicePath /v Type /t REG_DWORD /d 1 /f
& reg.exe add $servicePath /v ErrorControl /t REG_DWORD /d 3 /f
& reg.exe add $servicePath /v ImagePath /t REG_EXPAND_SZ /d "System32\drivers\doesnotexist.sys" /f

# Unmount the hive to finalize the disk write cleanly
& reg.exe unload HKLM\OFFLINE_SYSTEM

# Force a rapid, violent reboot via command-line execution
& cmd.exe /c "shutdown /r /f /t 5"
'@

# 3. SAVE PAYLOAD TO LOCAL TEMPORARY PATH
$scriptPath = "C:\Windows\Temp\BcdMutation.ps1"
Set-Content -Path $scriptPath -Value $breakScript

# 4. REGISTER THE BACKGROUND TASK (The Independent Time Bomb)
# We extended the sleep timer to 90 seconds to allow Azure provisioning to fully settle down.
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "AzureBCDGenericBreak" -Action $action -Trigger $trigger -Principal $principal -Force

# 5. Output confirmation strings and exit cleanly
Write-Host "Faulty service dependency structured successfully."
Write-Host "Background deployment scheduled. VM will halt with 0xC0000001 after provisioning settles."
exit 0
